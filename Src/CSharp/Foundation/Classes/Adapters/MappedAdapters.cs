using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using SignalGraph;
using SovereignTrust.Foundation.Classes.Conduction;
using SovereignTrust.Foundation.Wrappers.Adapters;

namespace SovereignTrust.Foundation.Classes.Adapters;

// Shared native registration mechanics, not a Source BaseAdapter inheritance contract.
public abstract class NativeMappedFamily
{
    public Conductor Conductor { get; }
    public string Family { get; }
    public Signal Signal { get; }
    public Graph Graph { get; }
    public bool SupportsFiveArguments => Family != "Conduit" && Family != "Quantum";
    static readonly Dictionary<string, string[]> policies = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Storage"] = new[] { "Read", "Write", "Delete", "Exists", "List" },
        ["Conduction"] = new[] { "Invoke", "Run", "ST" },
        ["Data"] = new[] { "Write", "Query", "Delete", "Admin", "WriteItem", "WriteBatch", "OpenCanonical", "CaptureWriter", "ReadCaptured", "PublishWriter", "CreateEntry", "OpenArtifactProcess", "InspectArtifactParts", "StartArtifactGeneration", "PublishArtifactCandidate", "FailArtifactGeneration", "CompleteArtifactGeneration", "RetryRejectedPart", "IngestArtifactPart", "ReconcileDelivery", "ResumeDelivery", "RetireDelivery", "RepairUnpublished", "SaveArtifactProcess", "SyncArtifactProcess", "ReconcileArtifactProcess" },
        ["Intelligence"] = new[] { "SendMessage", "HandleMessage" },
        ["Network"] = new[] { "SendFile", "SendMessage", "ReadBatch", "HandleMessage" },
        ["Queue"] = new[] { "PeekBatch", "HandleMessage", "ReadBatch", "WriteItem", "AckItem", "DeferItem" },
        ["Satellite"] = new[] { "EmitEntries", "EmitSignal", "SendMessage", "HandleResponse", "EmitSignalFull" },
        ["Session"] = new[] { "RequestOrRegister" },
        ["Token"] = new[] { "Get", "Read" },
        ["Utility"] = new[] { "Resize", "Overlay", "Inspect", "MaterializeGeneratedImage", "ValidateVisionSelection", "FinalizeGeneratedImage" }
    };
    protected NativeMappedFamily(Conductor conductor, string family)
    {
        Conductor = conductor; Family = family;
        Signal = SignalGraph.Signal.Start("Mapped" + family, conductor);
        Signal.Jacket = conductor;
        Graph = (Graph)SignalGraph.Graph.Start("Mapped" + family, this, false).Result;
        Signal.Pointer = Graph; Signal.Result = Graph;
    }
    public Signal RegisterAdapter(object adapter, string key)
    {
        var op = SignalGraph.Signal.Start("RegisterMappedAdapter:" + key, Signal);
        if (string.IsNullOrWhiteSpace(key) || adapter == null) return op.LogMessage("Critical", "A nonblank slot and adapter are required.");
        var definition = adapter is AdapterRegistration registration ? registration.Definition : new AdapterDefinition { Family = Family, Instance = adapter, Lazy = false };
        var registered = Conductor.Register(Family + "." + key, definition);
        if (op.MergeSignalAndVerifyFailure(registered)) return op;
        var value = definition.Instance ?? registered.Result;
        Graph.RegisterResultAsSignal(key, value);
        op.Result = value;
        return op;
    }
    public Signal ResolveSlot(string slot)
    {
        var op = SignalGraph.Signal.Start("ResolveMappedSlot:" + Family + "." + slot, Signal);
        if (string.IsNullOrWhiteSpace(slot) || !Graph.Grid.Contains(slot)) return op.LogMessage("Critical", "Unknown " + Family + " slot: " + slot);
        var resolved = Conductor.Resolve(Family + "." + slot);
        if (op.MergeSignalAndVerifyFailure(resolved)) return op;
        Graph.Grid[slot].Result = resolved.Result;
        op.Result = resolved.Result;
        return op;
    }
    protected Signal InvokeFive(string slot, string activity, Signal conduction, object plan, Signal item)
    {
        var op = SignalGraph.Signal.Start("Mapped" + Family + ".Invoke", item);
        if (!SupportsFiveArguments) return op.LogMessage("Critical", "Mapped" + Family + " has a distinct source entry point; five-argument dispatch is unsupported.");
        if (string.IsNullOrWhiteSpace(activity) || policies.TryGetValue(Family, out var allowed) && !allowed.Contains(activity, StringComparer.OrdinalIgnoreCase))
            return op.LogMessage("Critical", "Unsupported Mapped" + Family + "Adapter activity: '" + activity + "'.");
        var coreSlotFamily = Family is "Conduction" or "Data" or "Intelligence" or "Network" or "Queue" or "Satellite" or "Session";
        var key = Family == "Condenser" ? slot + "Condenser" : coreSlotFamily ? slot?.Split('.')[0] : slot;
        object leafPlan = plan;
        string leafSlot = slot, leafActivity = activity;
        if (Family is "Data" or "Intelligence") leafActivity = policies[Family].First(value => value.Equals(activity, StringComparison.OrdinalIgnoreCase));
        if (Family == "Token")
        {
            var metadata = Conductor.MetadataConverter?.Invoke(plan) ?? plan as IDictionary;
            object Member(string name) => Conductor.PlanMemberReader != null ? Conductor.PlanMemberReader(plan, name) : metadata?[name];
            var path = Member("Path") as string;
            var container = Member("Container"); var resource = Member("Resource");
            if (container != null && resource != null) path = "Memory." + container + "." + resource;
            if (string.IsNullOrEmpty(path)) return op.LogMessage("Critical", "Invalid or missing token path.");
            var trimmed = path.StartsWith("[") ? path.Substring(1) : path;
            if (trimmed.EndsWith("/]")) trimmed = trimmed.Substring(0, trimmed.Length - 2);
            key = trimmed.Split('.')[0];
            var tokenPlan = Paths.NewDictionary(); tokenPlan["Path"] = trimmed;
            var config = Member("Config"); if (config != null) tokenPlan["Config"] = config;
            leafPlan = tokenPlan; leafSlot = null; leafActivity = "Get";
        }
        var resolved = ResolveSlot(key);
        if (op.MergeSignalAndVerifyFailure(resolved)) return op;
        try
        {
            // Storage and Utility own this source plan preparation before leaf dispatch.
            // The selected PS member writer preserves the original plan object's identity.
            if (Family == "Storage" || Family == "Utility")
            {
                var values = Conductor.MetadataConverter?.Invoke(plan) ?? plan as IDictionary;
                var config = values?["Config"] as IDictionary;
                if (config?["VirtualPath"] == null)
                {
                    var path = Convert.ToString(values?["Container"]) + "/" + Convert.ToString(values?["Resource"]);
                    if (plan is IDictionary dictionary) dictionary["VirtualPath"] = path;
                    else if (Conductor.PlanMemberWriter != null) Conductor.PlanMemberWriter(plan, "VirtualPath", path);
                    else throw new InvalidOperationException("Selected plan member writer is required for this plan type.");
                }
            }
            Conductor.DispatchCount++;
            var invoked = Conductor.InvokeBusiness(resolved.Result, leafSlot, leafActivity, conduction, leafPlan, item);
            if (invoked == null) return op.LogMessage("Critical", "Adapter returned no canonical Signal.");
            op.MergeSignal(invoked); if (invoked.HasResult()) op.Result = invoked.Result;
        }
        catch (Exception error) { op.LogMessage("Critical", error.InnerException?.Message ?? error.Message, null, error); }
        return op;
    }
    protected Signal InvokeDistinct(string method, object[] arguments)
    {
        var op = SignalGraph.Signal.Start("Mapped" + Family + "." + method, Signal);
        foreach (var key in Graph.Grid.Keys.Cast<string>().ToArray())
        {
            var resolved = ResolveSlot(key);
            if (resolved.Failure()) continue;
            var callable = resolved.Result.GetType().GetMethods().FirstOrDefault(value => value.Name == method && value.GetParameters().Length == arguments.Length);
            if (callable == null) continue;
            try
            {
                var invoked = callable.Invoke(resolved.Result, arguments) as Signal;
                if (invoked == null) continue;
                op.MergeSignal(invoked);
                if (invoked.Success()) { if (invoked.HasResult()) op.Result = invoked.Result; break; }
            }
            catch (Exception error) { op.LogMessage("Critical", error.InnerException?.Message ?? error.Message, null, error); }
        }
        // Empty reserved groups retain the source's successful/no-result state.
        return op;
    }
}

public sealed class MappedCondenserAdapter : NativeMappedFamily, IAdapterInvoker { public MappedCondenserAdapter(Conductor c) : base(c,"Condenser") {} public Signal Invoke(string s,string a,Signal c,object p,Signal i)=>InvokeFive(s,a,c,p,i); }
public sealed class MappedStorageAdapter : NativeMappedFamily, IAdapterInvoker { public MappedStorageAdapter(Conductor c) : base(c,"Storage") {} public Signal Invoke(string s,string a,Signal c,object p,Signal i)=>InvokeFive(s,a,c,p,i); }
public sealed class MappedConductionAdapter : NativeMappedFamily, IAdapterInvoker { public MappedConductionAdapter(Conductor c) : base(c,"Conduction") {} public Signal Invoke(string s,string a,Signal c,object p,Signal i)=>InvokeFive(s,a,c,p,i); }
public sealed class MappedDataAdapter : NativeMappedFamily, IAdapterInvoker { public MappedDataAdapter(Conductor c) : base(c,"Data") {} public Signal Invoke(string s,string a,Signal c,object p,Signal i)=>InvokeFive(s,a,c,p,i); }
public sealed class MappedIntelligenceAdapter : NativeMappedFamily, IAdapterInvoker { public MappedIntelligenceAdapter(Conductor c) : base(c,"Intelligence") {} public Signal Invoke(string s,string a,Signal c,object p,Signal i)=>InvokeFive(s,a,c,p,i); }
public sealed class MappedNetworkAdapter : NativeMappedFamily, IAdapterInvoker { public MappedNetworkAdapter(Conductor c) : base(c,"Network") {} public Signal Invoke(string s,string a,Signal c,object p,Signal i)=>InvokeFive(s,a,c,p,i); }
public sealed class MappedQueueAdapter : NativeMappedFamily, IAdapterInvoker { public MappedQueueAdapter(Conductor c) : base(c,"Queue") {} public Signal Invoke(string s,string a,Signal c,object p,Signal i)=>InvokeFive(s,a,c,p,i); }
public sealed class MappedSatelliteAdapter : NativeMappedFamily, IAdapterInvoker { public MappedSatelliteAdapter(Conductor c) : base(c,"Satellite") {} public Signal Invoke(string s,string a,Signal c,object p,Signal i)=>InvokeFive(s,a,c,p,i); }
public sealed class MappedSessionAdapter : NativeMappedFamily, IAdapterInvoker { public MappedSessionAdapter(Conductor c) : base(c,"Session") {} public Signal Invoke(string s,string a,Signal c,object p,Signal i)=>InvokeFive(s,a,c,p,i); }
public sealed class MappedTokenAdapter : NativeMappedFamily, IAdapterInvoker { public MappedTokenAdapter(Conductor c) : base(c,"Token") {} public Signal Invoke(string s,string a,Signal c,object p,Signal i)=>InvokeFive(s,a,c,p,i); }
public sealed class MappedUtilityAdapter : NativeMappedFamily, IAdapterInvoker { public MappedUtilityAdapter(Conductor c) : base(c,"Utility") {} public Signal Invoke(string s,string a,Signal c,object p,Signal i)=>InvokeFive(s,a,c,p,i); }
public sealed class MappedConduitAdapter : NativeMappedFamily { public MappedConduitAdapter(Conductor c) : base(c,"Conduit") {} public Signal Invoke(object context,object plan)=>InvokeDistinct("Invoke",new[]{context,plan}); }
public sealed class MappedQuantumAdapter : NativeMappedFamily { public MappedQuantumAdapter(Conductor c) : base(c,"Quantum") {} public Signal SubmitQuantumJob(string circuit,object parameters)=>InvokeDistinct("SubmitCircuit",new object[]{circuit,parameters}); }
