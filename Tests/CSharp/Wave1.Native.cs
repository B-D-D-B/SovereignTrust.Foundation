using System.Collections;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using Newtonsoft.Json.Linq;
using SignalGraph;

// Unit/component characterization only. Integration remains the PowerShell launcher.
internal static class Program
{
    private static readonly List<object> Results = new();
    private static int failures;
    private static void Case(string id, Action assertion)
    {
        try { assertion(); Results.Add(new { Id = id, Pass = true }); }
        catch (Exception error) { failures++; Results.Add(new { Id = id, Pass = false, Error = error.Message }); Console.Error.WriteLine($"ST_WAVE1_ASSERT: {id}: {error.Message}"); }
    }
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static Dictionary<string, object> D(params object[] pairs)
    {
        var result = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
        for (int i = 0; i < pairs.Length; i += 2) result[(string)pairs[i]] = pairs[i + 1];
        return result;
    }
    private static Signal S(object? value = null) { var s = Signal.Start("Wave1"); s.SetResult(value); return s; }
    private static object Identity(string path) => new { Path = Path.GetFullPath(path), Sha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))) };
    private static int Main(string[] args)
    {
        try
        {
            string? receipt = null, inputs = null, catalog = null; bool selector = false, deliberate = false;
            for (int i = 0; i < args.Length; i++)
                switch (args[i])
                {
                    case "--wave": Require(!selector && ++i < args.Length && args[i] == "1", "Only Wave 1 is implemented."); selector = true; break;
                    case "--all-offline": Require(!selector, "Duplicate selector."); selector = true; break;
                    case "--receipt": receipt = args[++i]; break;
                    case "--inputs": inputs = args[++i]; break;
                    case "--catalog": catalog = args[++i]; break;
                    case "--deliberate-failure": deliberate = true; break;
                    default: throw new ArgumentException("Unknown selector: " + args[i]);
                }
            Require(selector && receipt != null && Path.IsPathFullyQualified(receipt) && !File.Exists(receipt) && Directory.Exists(Path.GetDirectoryName(receipt)), "Explicit selector and new absolute run-owned receipt required.");
            Require(inputs != null && Path.IsPathFullyQualified(inputs) && catalog != null && Path.IsPathFullyQualified(catalog), "Exact source/catalog inputs required.");
            using var source = JsonDocument.Parse(File.ReadAllText(inputs!));
            foreach (var file in source.RootElement.EnumerateArray())
                Require(Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(file.GetProperty("Path").GetString()!))) == file.GetProperty("Sha256").GetString(), "Source/config input drift.");
            foreach (var item in new (string Id, object? Value, Type? Type)[] { ("false", false, typeof(bool)), ("zero", 0, typeof(int)), ("empty", "", typeof(string)), ("null", null, null) })
                Case("value." + item.Id, () => { var s = S(item.Value); Require(s.HasResult() == (item.Value != null) && s.Result?.GetType() == item.Type && Equals(s.Result, item.Id == "false" && deliberate ? true : item.Value), "Native value/type/presence differs."); });
            Case("value.missing", () => Require(!Signal.Start("missing").HasResult(), "Missing result became present."));
            foreach (int count in new[] { 0, 1, 3 })
                Case("array." + count, () => { var array = Enumerable.Range(0, count).Cast<object>().ToArray(); var s = S(array); Require(s.HasResult() && ReferenceEquals(array, s.Result) && ((object[])s.Result).Length == count, "Array shape/identity differs."); });
            Case("severity.merge", () => { var w = S(); w.LogWarning("wave1 warning"); var c = S(); c.LogCritical("wave1 critical"); var m = S(); m.MergeSignal(w, c); Require(m.Failure() && m.Level == "Critical", "Critical merge lost failure."); });
            Case("canonical.start.named.absent.reverse", () => { var parent = S(); var s = Signal.Start("literal", parent); Require(s.Name == "literal" && !s.HasResult() && ReferenceEquals(s.ReversePointer, parent), "Start inferred a result or lost reverse identity."); });
            Case("canonical.typed.presence", () => { var absent = new Signal<int>(); var zero = new Signal<int>(0); var no = new Signal<bool>(false); Require(!absent.HasResult() && absent.Result == 0 && !((Signal)absent).HasResult() && zero.HasResult() && ((ISignal<int>)zero).Result == 0 && no.HasResult() && !no.Result, "Typed absent/zero/false backing presence differs."); });
            Case("canonical.public.surface", () => { var t = typeof(Signal); Require(!t.GetMethods().Any(m => m.Name is "Named" or "StartSignal" or "LogParity" or "PSLogCritical") && t.GetProperty("Failure") == null && t.GetProperty("Success") == null && t.Assembly.GetType("SignalGraph.SignalFeedbackEntry") == null && t.Assembly.GetType("SignalGraph.SignalFeedbackLevel") == null && typeof(SignalEntry).Name == "SignalEntry", "Obsolete factories/facades/status properties/enums remain."); });
            Case("canonical.logger.return.identity", () => { var s = S(); Require(ReferenceEquals(s, s.LogInformation("info")) && ReferenceEquals(s, s.LogInformation("empty", Array.Empty<string>())) && ReferenceEquals(s, s.LogWarning("warn", null)) && ReferenceEquals(s, s.LogMessage("Information", "message", null, null)) && ReferenceEquals(s, s.LogCritical("critical", Array.Empty<string>())), "Canonical logger returned another object."); });
            Case("canonical.logger.exception.tags", () => { var s = S(); var error = new InvalidOperationException("canonical exception"); Require(ReferenceEquals(s, s.LogCritical("failed", new[] { "Audit" }, error)) && s.Failure() && s.Entries.Last().Exception?.Message == error.Message && s.Entries.Last().Tags.Contains("Audit"), "Exception third argument or tags lost."); });
            Case("canonical.logger.verbose.retry.tags", () => { var s = S(); s.LogVerbose("verbose"); s.LogRetry("retry"); Require(s.Level == "Information" && s.Entries.All(e => e.Level == "Information") && s.Entries[0].Tags.Contains("Verbose") && s.Entries[1].Tags.Contains("Retry"), "Verbose/Retry became severity values."); });
            Case("canonical.level.recovery.mute", () => { var s = S(); s.UpdateLevel("critical"); Require(s.Failure(), "Critical failed equality."); Require(ReferenceEquals(s, s.LogRecovery("recover")) && s.Level == "Warning" && s.Success(), "Recovery did not lower current level."); s.LogCritical("again"); Require(ReferenceEquals(s, s.LogMute("mute")) && s.Level == "Warning" && !s.Failure(), "Mute recomputed historical maximum."); });
            Case("canonical.level.invalid.transactional", () => { var s = S(); bool rejected = false; try { s.UpdateLevel("VerboseInformation"); } catch (ArgumentException) { rejected = true; } Require(rejected && s.Level == "Information" && s.Entries.Count == 0, "Invalid level mutated state."); });
            Case("canonical.dto.text.entry.fields", () => { var s = S(false); s.LogWarning("dto", new[] { "Audit" }); var dto = JObject.Parse(s.ToJson()); var entry = (JObject)dto["Entries"]![0]!; Require((string?)dto["Level"] == "Warning" && (string?)entry["Level"] == "Warning" && entry["Nature"] == null && entry["MessageFull"] == null && entry["Version"] == null && entry["Signal"] == null && dto["ReversePointer"] == null, "DTO exposes old severity/entry/back-reference shape."); });
            Case("canonical.dto.user.dictionary", () => { var s = S(D("Name", "user", "Level", "Warning", "Entries", Array.Empty<object>())); var r = Signal.FromJson(s.ToJson()); Require(r.Result is IDictionary value && (string)value["Name"]! == "user" && r.Result is not Signal, "User dictionary inferred as a native Signal."); });
            Case("canonical.dto.cycle.reject.guidance", () => { var s = S(); s.SetResult(s); bool rejected = false; try { s.ToJson(); } catch (Exception error) { rejected = error.Message.Contains("ToGraphJson", StringComparison.OrdinalIgnoreCase); } Require(rejected, "Ordinary DTO cycle accepted or lacks graph guidance."); });
            var graph = (Graph)Graph.Start("Wave1").Result; var member = S(D("Count", 1));
            member.Pointer = graph; member.Jacket = member; member.Control = member; graph.RegisterSignal("Member", member);
            Case("graph.references", () => Require(ReferenceEquals(member.Pointer, graph) && ReferenceEquals(member.Jacket, member) && ReferenceEquals(member.Control, member), "Live cycle references copied."));
            Case("graph.case.shared", () => { ((IDictionary)graph.Grid["member"].Result)["Count"] = 2; Require(graph.Grid.Count == 1 && (int)((IDictionary)member.Result)["Count"]! == 2, "Case lookup/shared mutation differs."); });
            var rows = new object[] { D("Name", "Key", "Value", 0), D("Name", "key", "Value", false) };
            Case("dictionary.case.overwrite", () => { var d = GraphUtilities.ConvertToDictionary(rows, valueProperty: "Value"); Require(d.Count == 1 && d["KEY"] is bool b && !b, "Ignore-case/native false overwrite differs."); });
            Case("dictionary.policies", () => {
                Require(GraphUtilities.ConvertToDictionary(rows, caseSensitive: true).Count == 2, "Case-sensitive distinct keys lost.");
                Require((int)GraphUtilities.ConvertToDictionary(rows, valueProperty: "Value", onDuplicate: DuplicatePolicy.Skip)["key"] == 0, "Skip overwrote first.");
                Require(((IList)GraphUtilities.ConvertToDictionary(rows, valueProperty: "Value", onDuplicate: DuplicatePolicy.Append)["key"]).Count == 2, "Append lost cardinality.");
                bool rejected = false; try { GraphUtilities.ConvertToDictionary(rows, onDuplicate: DuplicatePolicy.Error); } catch (ArgumentException) { rejected = true; } Require(rejected, "Duplicate Error accepted.");
            });
            Case("utilities.array", () => { var item = S(); item.Jacket = S(rows); var op = GraphUtilities.ResolveGraphForJsonArray(S(), D(), item); var built = (Graph)op.Result; Require(!op.Failure() && op.Level == "Warning" && built.Grid.Count == 1 && ReferenceEquals(((Signal)built.Grid["key"].Jacket).Result, rows[1]), "Default array builder/later duplicate/original jacket differs."); Require(GraphUtilities.ResolveGraphForJsonArray(S(), D(), S(new[] { D("Other", 1) }), "@").Failure(), "Missing identifier accepted."); });
            Case("utilities.array.empty", () => Require(((Graph)GraphUtilities.ResolveGraphForJsonArray(S(), D(), S(Array.Empty<object>()), "@").Result).Grid.Count == 0, "Empty array produced a member."));
            Case("utilities.injection", () => { var dynamic = D("Value", false); var op = GraphUtilities.ResolveGraphPlanInjectionContext(D(), D(), Array.Empty<object>(), S(), member, dynamic); var context = (InjectionContext)op.Result; Require(!op.Failure() && ReferenceEquals(context.SourceItem, dynamic) && context.TargetSignal == null && context.GraphPointer == null, "Default injection context changed identity/target."); });
            Case("utilities.fork", () => { var op = GraphUtilities.NewSignalPointerFork(member, "fork", copyJacket: true, copyResult: true); var fork = (Signal)op.Result; Require(!op.Failure() && !ReferenceEquals(fork.Pointer, graph) && ReferenceEquals(((Graph)fork.Pointer).Grid["Member"], member) && ReferenceEquals(fork.Jacket, member.Jacket) && ReferenceEquals(fork.Result, member.Result), "Fork containers/shared references differ."); });
            Case("utilities.fork.collision", () => { var target = (Graph)Graph.Start().Result; var original = S("target"); target.RegisterSignal("Member", original); var op = GraphUtilities.NewSignalPointerFork(member, "collision", targetGraph: target, collisionAction: ForkCollisionAction.Error); Require(op.Failure() && target.Grid.Count == 1 && ReferenceEquals(target.Grid["Member"], original), "Error collision mutated target."); });
            // Independent documented native version-2 contract; PS GraphJSON is known unsupported.
            graph.RegisterSignal("Shared", member); member.ReversePointer = S("omitted"); member.AddTag("persist"); member.AddProperty("native", false); member.LogWarning("retained entry");
            member.Result = D("Values", new object?[] { false, 0, "", null }, "Nested", D("Value", "complete"));
            string json = graph.ToJson(); var restoredOp = Graph.FromJson(json); var restored = (Graph)restoredOp.Result; var rs = restored.Grid["Member"];
            Case("graph.roundtrip", () => { var envelope = JObject.Parse(json); Require(!restoredOp.Failure() && (string?)envelope["format"] == "SignalGraph" && (int?)envelope["version"] == 2 && restored.GetKeys().SequenceEqual(new object[] { "Member", "Shared" }), "Native envelope/order/round-trip differs."); });
            Case("graph.cycle.roundtrip", () => Require(ReferenceEquals(rs.Pointer, restored) && ReferenceEquals(rs.Jacket, rs) && ReferenceEquals(rs.Control, rs) && ReferenceEquals(rs, restored.Grid["Shared"]), "Native shared graph-node cycle lost."));
            Case("graph.payload", () => { var d = (IDictionary)rs.Result; var a = (IList)d["Values"]!; Require(a.Count == 4 && a[0] is bool b && !b && Convert.ToInt64(a[1]) == 0 && (string)a[2]! == "" && a[3] == null && (string)((IDictionary)d["Nested"]!)["Value"]! == "complete", "Dictionary/list/scalar payload reconstruction differs."); });
            Case("graph.metadata.omissions", () => Require(rs.Id == member.Id && rs.CreatedDate == member.CreatedDate && rs.Tags.Contains("persist") && rs.GetProperty("native") is bool b && !b && rs.Entries.Any(e => e.Message == "retained entry") && rs.ReversePointer == null && rs.Entries.All(e => e.Signal == null), "Metadata persistence or documented omission differs."));
            Case("signal.dto.json", () => { var s = S(false); s.LogWarning("legacy"); var text = s.ToJson(); var r = Signal.FromJson(text); Require(r.Result is bool b && !b && r.Level == "Warning" && (string?)JObject.Parse(text)["Level"] == "Warning" && JObject.Parse(text)["LevelName"] == null, "Canonical acyclic DTO contract lost."); bool rejected = false; try { Signal.FromJson("{"); } catch (Newtonsoft.Json.JsonException) { rejected = true; } Require(rejected, "Malformed Signal JSON did not throw canonical JsonException."); });
            void Invalid(string id, Action<JObject> mutate) => Case("graph.reject." + id, () => { var envelope = JObject.Parse(json); mutate(envelope); Require(Graph.FromJson(envelope.ToString()).Failure(), "Malformed native graph accepted."); });
            Case("graph.reject.json", () => Require(Graph.FromJson("{").Failure(), "Malformed JSON accepted."));
            Invalid("unknownid", e => e["root"]!["ref"] = "missing");
            Invalid("kind", e => e["nodes"]![0]!["kind"] = "System.IO.FileInfo");
            Invalid("duplicateid", e => ((JArray)e["nodes"]!).Add(e["nodes"]![0]!.DeepClone()));
            Invalid("enum", e => e["nodes"]!.OfType<JObject>().First(n => (string?)n["kind"] == "signal")["level"] = 999);
            Invalid("version1", e => e["version"] = 1);
            Invalid("member", e => e["nodes"]!.OfType<JObject>().First(n => (string?)n["kind"] == "graph")["grid"]![0]!["value"] = 1);
            Case("graph.depth64", () => { object payload = 0; for (int i = 0; i < 62; i++) payload = D("x", payload); var g = (Graph)Graph.Start().Result; g.RegisterSignal("deep", S(payload)); Require(!Graph.FromJson(g.ToJson()).Failure(), "Documented depth64 boundary rejected."); });
            Case("graph.reject.depth.write", () => { object payload = 0; for (int i = 0; i < 63; i++) payload = D("x", payload); var g = (Graph)Graph.Start().Result; g.RegisterSignal("deep", S(payload)); bool rejected = false; try { g.ToJson(); } catch (Newtonsoft.Json.JsonException error) { rejected = error.Message.Contains("depth", StringComparison.OrdinalIgnoreCase); } Require(rejected, "Over64 depth did not report depth rejection in writer."); });
            Case("graph.reject.depth.read", () => { var envelope = JObject.Parse(json); JToken payload = new JValue(0); for (int i = 0; i < 63; i++) { var pairs = new JArray(); pairs.Add(new JArray("x", payload)); payload = new JObject { ["kind"] = "dictionary", ["items"] = pairs }; } envelope["nodes"]!.OfType<JObject>().First(n => (string?)n["name"] == "Wave1")["result"] = payload; var op = Graph.FromJson(envelope.ToString()); Require(op.Failure() && op.Entries.Where(entry => entry.Level == "Critical").Any(entry => entry.Exception is Newtonsoft.Json.JsonException error && error.Message.Contains("depth", StringComparison.OrdinalIgnoreCase)), "Well-formed over64 payload did not report depth rejection in reader."); });
            Case("catalog.coverage", () => { using var doc = JsonDocument.Parse(File.ReadAllText(catalog!)); var r = doc.RootElement; Require(r.GetProperty("OwnerCount").GetInt32() == 28 && r.GetProperty("ActivityCount").GetDouble() == 103 && r.GetProperty("Owners").GetArrayLength() == 28, "Catalog denominator changed."); var ids = r.GetProperty("Owners").EnumerateArray().SelectMany(o => o.GetProperty("Activities").EnumerateArray()).Select(a => a.GetProperty("CaseId").GetString()).ToArray(); Require(ids.Length == 103 && ids.Distinct().Count() == 103, "Catalog IDs omitted/duplicated."); });
            var assemblies = new[] { typeof(Signal).Assembly, typeof(JObject).Assembly, typeof(Microsoft.Extensions.Logging.ILogger).Assembly, Assembly.GetExecutingAssembly() }.Select(a => new { a.FullName, File = Identity(a.Location) }).ToArray();
            var result = new { Scope = "Wave1 native unit/component characterization; no native plan/storage/provider implementation claimed", Command = Environment.GetCommandLineArgs(), EntryPointArguments = args, Runtime = Environment.Version.ToString(), OS = System.Runtime.InteropServices.RuntimeInformation.OSDescription, Architecture = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString(), SourceInputs = Identity(inputs!), Catalog = Identity(catalog!), Assemblies = assemblies, DeliberateFailure = deliberate, Cases = Results, PassCount = Results.Count - failures, FailCount = failures, SkipCount = 0, Total = Results.Count, Pass = failures == 0, KnownUnsupportedPSGraphJson = "Source04/copy04 retained; separate documented native contract tested here" };
            using var stream = new FileStream(receipt!, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            System.Text.Json.JsonSerializer.Serialize(stream, result, new JsonSerializerOptions { WriteIndented = true });
            Console.WriteLine($"NATIVE {(failures == 0 ? "PASS" : "FAIL")} {Results.Count - failures}/{failures}/{Results.Count}");
            return failures == 0 ? 0 : 1;
        }
        catch (Exception error) { Console.Error.WriteLine("ST_WAVE1_INPUT_OR_RUNTIME: " + error.Message); return 2; }
    }
}
