using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Win32.SafeHandles;

namespace SovereignTrust.AtomicFiles;

public sealed class StorageException(string code) : IOException(code);
public sealed record FileValue(string Text, string Revision, string ByteHash);
public sealed record Receipt(Guid OperationId, string Binding, string Resource, string Revision, string ByteHash, DateTime VerifiedUtc);
internal sealed record Marker(Guid OperationId, string Binding);
internal sealed record Intent(Guid OperationId, string Binding, string Resource, string? ExpectedRevision, string ByteHash, string Text);
internal sealed record Worker(int Pid, long StartedUtcTicks, string Instance);
public sealed record NoWriteProof(Guid OperationId, string Binding, string? OriginalRevision, string EventReference, DateTime VerifiedUtc);

/// <summary>Single-machine NTFS publication. Caller must additionally enforce OS write authority.
/// The lock protects every operation using this root, across processes; it is not an ACL.</summary>
public sealed class AtomicStore : IDisposable
{
    public const long Capacity = 512L * 1024 * 1024;
    private const long Reserve = 64L * 1024 * 1024;
    private const string StreamName = ":SovereignTrust.Publication";
    private static readonly UTF8Encoding Utf8 = new(false, true);
    private readonly FileStream owner;
    private readonly string control;
    private bool disposed;
    public string Root { get; }
    public string Identity { get; }
    // Tests can pause/terminate at real boundaries. This callback is never supplied by plan content.
    public Action<string>? Boundary { get; set; }

    public AtomicStore(string root, bool recoverDeadOwner = false)
    {
        if (!OperatingSystem.IsWindows()) throw new StorageException("WindowsNtfsRequired");
        Root = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar);
        if (Root.StartsWith("\\\\", StringComparison.Ordinal) || !Directory.Exists(Root)) throw new StorageException("LocalExistingRootRequired");
        var drive = new DriveInfo(Path.GetPathRoot(Root)!);
        if (drive.DriveType != DriveType.Fixed || drive.DriveFormat != "NTFS") throw new StorageException("LocalNtfsRequired");
        CheckAncestors(Root);
        Identity = FileIdentity(Root, true);
        control = Path.Combine(Root, ".st-publication");
        Directory.CreateDirectory(control); CheckAncestors(control);
        string lockPath = Path.Combine(control, "owner.lock");
        if (File.Exists(lockPath)) CheckFile(lockPath);
        owner = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None, 4096, FileOptions.WriteThrough);
        try
        {
            string statePath = Path.Combine(control, "owner.json");
            if (File.Exists(statePath))
            {
                CheckFile(statePath);
                var prior = JsonSerializer.Deserialize<Worker>(File.ReadAllText(statePath, Utf8))!;
                if (!recoverDeadOwner) throw new StorageException("ExplicitOwnerRecoveryRequired");
                bool dead;
                try { using var p = Process.GetProcessById(prior.Pid); dead = p.HasExited || p.StartTime.ToUniversalTime().Ticks != prior.StartedUtcTicks; }
                catch (ArgumentException) { dead = true; }
                // Access denied/unknown process identity is not proof of death.
                if (!dead) throw new StorageException("PreviousWorkerStillAlive");
            }
            using var current = Process.GetCurrentProcess();
            DurableReplace(statePath, JsonSerializer.Serialize(new Worker(current.Id, current.StartTime.ToUniversalTime().Ticks, Guid.NewGuid().ToString())));
        }
        catch { owner.Dispose(); throw; }
    }
    public static string Hash(byte[] data) => Convert.ToHexString(SHA256.HashData(data));
    public static string HashText(string text) => Hash(Utf8.GetBytes(text));
    private void Ready() { ObjectDisposedException.ThrowIf(disposed, this); }
    private static void CheckAncestors(string path)
    {
        for (var p = new DirectoryInfo(path); p != null; p = p.Parent)
            if ((p.Attributes & FileAttributes.ReparsePoint) != 0) throw new StorageException("ReparsePathRejected");
    }
    private static void CheckFile(string path)
    {
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw new StorageException("ReparsePathRejected");
        using var h = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        if (!GetFileInformationByHandle(h, out var info)) throw new System.ComponentModel.Win32Exception();
        if (info.Links != 1) throw new StorageException("HardLinkRejected");
    }
    public string Resolve(string resource)
    {
        Ready();
        if (string.IsNullOrWhiteSpace(resource) || resource.Contains('\\') || Path.IsPathRooted(resource)) throw new StorageException("InvalidResource");
        foreach (string segment in resource.Split('/'))
        {
            string stem = segment.Split('.')[0].ToUpperInvariant();
            if (segment.Length == 0 || segment is "." or ".." || segment.EndsWith('.') || segment.EndsWith(' ') || segment.Contains('~') ||
                segment.Any(c => c < 32 || "<>:\"|?*".Contains(c)) || segment.Equals(".st-publication", StringComparison.OrdinalIgnoreCase) ||
                stem is "CON" or "PRN" or "AUX" or "NUL" || System.Text.RegularExpressions.Regex.IsMatch(stem, "^(COM|LPT)[0-9¹²³]$")) throw new StorageException("InvalidResource");
        }
        string full = Path.GetFullPath(Path.Combine(Root, resource));
        if (!full.StartsWith(Root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new StorageException("InvalidResource");
        string? parent = Path.GetDirectoryName(full);
        while (parent != null && !Directory.Exists(parent)) parent = Path.GetDirectoryName(parent);
        if (parent != null) CheckAncestors(parent);
        if (File.Exists(full)) CheckFile(full);
        return full;
    }
    private Marker? GetMarker(string full)
    {
        try { return JsonSerializer.Deserialize<Marker>(File.ReadAllText(full + StreamName, Utf8)); }
        catch (FileNotFoundException) { return null; }
    }
    public FileValue? Read(string resource)
    {
        string full = Resolve(resource);
        if (!File.Exists(full)) return null;
        byte[] bytes = File.ReadAllBytes(full);
        if (bytes.Length > 8 * 1024 * 1024) throw new StorageException("SourceByteLimit");
        var marker = GetMarker(full);
        string hash = Hash(bytes);
        string revision = HashText(JsonSerializer.Serialize(new { Identity, Resource = resource.ToUpperInvariant(), hash, marker }));
        return new(Utf8.GetString(bytes), revision, hash);
    }
    private string OpPath(Guid operation, string extension) => Path.Combine(control, operation.ToString("D") + extension);
    private string Binding(Guid operation, string resource, string? expected, string hash) =>
        HashText(JsonSerializer.Serialize(new { Identity, Operation = operation, Resource = resource.ToUpperInvariant(), Expected = expected, Hash = hash }));
    public Receipt Publish(Guid operation, string resource, string? expectedRevision, string text)
    {
        Ready(); if (operation == Guid.Empty) throw new StorageException("OperationIdRequired");
        string full = Resolve(resource), hash = HashText(text), binding = Binding(operation, resource, expectedRevision, hash);
        if (Utf8.GetByteCount(text) > 8 * 1024 * 1024) throw new StorageException("SourceByteLimit");
        string intentPath = OpPath(operation, ".intent.json");
        if (File.Exists(intentPath))
        {
            var original = JsonSerializer.Deserialize<Intent>(File.ReadAllText(intentPath, Utf8))!;
            if (original.Binding != binding) throw new StorageException("OperationIdReuse");
            if (File.Exists(OpPath(operation,".aborted.json"))) throw new StorageException("OperationAbandoned");
            return Recover(operation) ?? throw new StorageException("PublicationUnknown");
        }
        // Reserve room for receipts/owner release/recovery. No unbounded compaction is implied.
        foreach (string unresolved in Directory.EnumerateFiles(control, "*.intent.json"))
            if (!File.Exists(unresolved.Replace(".intent.json", ".receipt.json", StringComparison.Ordinal)) && !File.Exists(unresolved.Replace(".intent.json", ".aborted.json", StringComparison.Ordinal))) throw new StorageException("UnresolvedPublicationBlocksAdmission");
        long size = Directory.EnumerateFiles(control, "*", SearchOption.AllDirectories).Sum(p => new FileInfo(p).Length);
        string intent = JsonSerializer.Serialize(new Intent(operation, binding, resource, expectedRevision, hash, text));
        if (size + Utf8.GetByteCount(intent) > Capacity - Reserve) throw new StorageException("PublicationCapacityExceeded");
        if (Read(resource)?.Revision != expectedRevision) throw new StorageException("RevisionConflict");
        Boundary?.Invoke("Validated");
        DurableReplace(intentPath, intent); Boundary?.Invoke("IntentFlushed");
        Directory.CreateDirectory(Path.GetDirectoryName(full)!); CheckAncestors(Path.GetDirectoryName(full)!);
        string temporary = full + ".st-" + operation.ToString("N") + ".tmp";
        // A retained temporary file is evidence; never overwrite it on another attempt.
        WriteNew(temporary, text);
        WriteNew(temporary + StreamName, JsonSerializer.Serialize(new Marker(operation, binding)));
        Boundary?.Invoke("CandidateFlushed");
        // The owner remains held from validation through receipt. This does not fence bypass writers.
        MoveDurable(temporary, full); Boundary?.Invoke("DestinationReplaced");
        return Recover(operation) ?? throw new StorageException("PublicationUnknown");
    }
    public Receipt? Recover(Guid operation)
    {
        Ready(); string receiptPath = OpPath(operation, ".receipt.json");
        string intentPath = OpPath(operation, ".intent.json");
        if (!File.Exists(intentPath)) throw new StorageException("UnknownOperation");
        var intent = JsonSerializer.Deserialize<Intent>(File.ReadAllText(intentPath, Utf8))!;
        string binding = Binding(operation, intent.Resource, intent.ExpectedRevision, intent.ByteHash);
        if (intent.OperationId != operation || intent.Binding != binding || HashText(intent.Text) != intent.ByteHash) throw new StorageException("CorruptIntent");
        if (File.Exists(receiptPath))
        {
            var prior = JsonSerializer.Deserialize<Receipt>(File.ReadAllText(receiptPath, Utf8))!;
            if (prior.OperationId != operation || prior.Binding != binding || prior.ByteHash != intent.ByteHash) throw new StorageException("CorruptReceipt");
            return prior;
        }
        string full = Resolve(intent.Resource);
        if (!File.Exists(full)) return null;
        var marker = GetMarker(full); var value = Read(intent.Resource)!;
        if (marker?.OperationId != operation || marker.Binding != binding || value.ByteHash != intent.ByteHash) return null;
        Boundary?.Invoke("DestinationVerified");
        var receipt = new Receipt(operation, binding, intent.Resource, value.Revision, value.ByteHash, DateTime.UtcNow);
        DurableReplace(receiptPath, JsonSerializer.Serialize(receipt)); Boundary?.Invoke("ReceiptFlushed");
        return receipt;
    }
    public NoWriteProof AbandonUnpublished(Guid operation,string resource,string? expectedRevision,string text,string eventReference)
    {
        Ready();if(string.IsNullOrWhiteSpace(eventReference))throw new StorageException("ExplicitRepairEventRequired");
        string full=Resolve(resource),hash=HashText(text),binding=Binding(operation,resource,expectedRevision,hash);
        if(File.Exists(OpPath(operation,".receipt.json")))throw new StorageException("PublicationAlreadyProven");
        string intentPath=OpPath(operation,".intent.json");
        if(File.Exists(intentPath))
        {
            var intent=JsonSerializer.Deserialize<Intent>(File.ReadAllText(intentPath,Utf8))!;
            if(intent.Binding!=binding)throw new StorageException("OperationIdReuse");
        }
        // Acquired root lock plus synchronous writes excludes an in-flight old writer.
        // The original revision includes the operation marker: equal bytes alone are insufficient.
        if(Read(resource)?.Revision!=expectedRevision || File.Exists(full) && GetMarker(full)?.OperationId==operation)throw new StorageException("NoWriteNotProven");
        string proofPath=OpPath(operation,".aborted.json");
        if(File.Exists(proofPath))
        {
            var prior=JsonSerializer.Deserialize<NoWriteProof>(File.ReadAllText(proofPath,Utf8))!;
            if(prior.Binding!=binding)throw new StorageException("CorruptNoWriteProof");return prior;
        }
        if(!File.Exists(intentPath))DurableReplace(intentPath,JsonSerializer.Serialize(new Intent(operation,binding,resource,expectedRevision,hash,text)));
        var proof=new NoWriteProof(operation,binding,expectedRevision,eventReference,DateTime.UtcNow);
        DurableReplace(proofPath,JsonSerializer.Serialize(proof));return proof;
    }
    private static void WriteNew(string path, string text)
    {
        using var file = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough);
        file.Write(Utf8.GetBytes(text)); file.Flush(true);
    }
    private static void DurableReplace(string path, string text)
    {
        string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        WriteNew(temporary, text); MoveDurable(temporary, path);
    }
    private static void MoveDurable(string from, string to)
    {
        if (!MoveFileEx(from, to, 0x1 | 0x8)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }
    private static string FileIdentity(string path, bool directory)
    {
        using var h = CreateFile(path, 0, 7, IntPtr.Zero, 3, directory ? 0x02000000u : 0u, IntPtr.Zero);
        if (h.IsInvalid || !GetFileInformationByHandle(h, out var info)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        return $"{info.Volume:X8}:{info.IndexHigh:X8}{info.IndexLow:X8}";
    }
    public void Dispose()
    {
        if (disposed) return;
        try { File.Delete(Path.Combine(control, "owner.json")); }
        finally { disposed = true; owner.Dispose(); }
    }
    [StructLayout(LayoutKind.Sequential)] private struct FileInfoNative
    { public uint Attributes; public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write; public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow; }
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] private static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInfoNative info);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool MoveFileEx(string from, string to, uint flags);
}
