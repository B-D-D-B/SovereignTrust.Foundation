using System.Security.AccessControl;
using System.Security.Principal;

namespace SovereignTrust.AtomicFiles;

/// <summary>Conservative local ACL admission check. Administrators/SYSTEM are privileged
/// maintenance authorities. Ordinary workers must not possess the publisher token.</summary>
public static class PublisherAuthority
{
    public static void Validate(string root,string publisherSid)
    {
        if(!OperatingSystem.IsWindows())throw new StorageException("WindowsNtfsRequired");
        using var identity=WindowsIdentity.GetCurrent();
        if(identity.User?.Value!=publisherSid || new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))throw new StorageException("DedicatedNonAdministratorPublisherRequired");
        var allowed=new HashSet<string>(StringComparer.Ordinal){publisherSid,"S-1-5-18","S-1-5-32-544"};
        const FileSystemRights writes=FileSystemRights.WriteData|FileSystemRights.AppendData|FileSystemRights.WriteAttributes|FileSystemRights.WriteExtendedAttributes|FileSystemRights.Delete|FileSystemRights.DeleteSubdirectoriesAndFiles|FileSystemRights.ChangePermissions|FileSystemRights.TakeOwnership;
        void Check(FileSystemInfo item)
        {
            if((item.Attributes&FileAttributes.ReparsePoint)!=0)throw new StorageException("ReparsePathRejected");
            FileSystemSecurity acl=item is DirectoryInfo directory?directory.GetAccessControl():((FileInfo)item).GetAccessControl();
            string owner=acl.GetOwner(typeof(SecurityIdentifier))?.Value??throw new StorageException("UnknownCanonicalOwner");
            if(!allowed.Contains(owner))throw new StorageException("UntrustedCanonicalOwner");
            foreach(FileSystemAccessRule rule in acl.GetAccessRules(true,true,typeof(SecurityIdentifier)))
                if(rule.AccessControlType==AccessControlType.Allow && (rule.FileSystemRights&writes)!=0 && !allowed.Contains(rule.IdentityReference.Value))throw new StorageException("UntrustedCanonicalWritePermission");
        }
        var directory=new DirectoryInfo(Path.GetFullPath(root));Check(directory);
        foreach(var item in directory.EnumerateFileSystemInfos("*",SearchOption.AllDirectories))Check(item);
        // A writable parent can delete/replace a protected child directory independently.
        for(var parent=directory.Parent;parent!=null;parent=parent.Parent)
        {
            if((parent.Attributes&FileAttributes.ReparsePoint)!=0)throw new StorageException("ReparsePathRejected");
            var acl=parent.GetAccessControl();
            foreach(FileSystemAccessRule rule in acl.GetAccessRules(true,true,typeof(SecurityIdentifier)))
                if(rule.AccessControlType==AccessControlType.Allow && (rule.FileSystemRights&(FileSystemRights.DeleteSubdirectoriesAndFiles|FileSystemRights.ChangePermissions|FileSystemRights.TakeOwnership))!=0 && !allowed.Contains(rule.IdentityReference.Value))throw new StorageException("UntrustedParentReplacementPermission");
        }
    }
}
