using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using SignalGraph;
using SovereignTrust.Foundation.Classes.Adapters;
using SovereignTrust.Foundation.Wrappers.Adapters;

namespace SovereignTrust.Foundation.Classes.Conduction;

public sealed partial class Conductor
{
    readonly Dictionary<string, NativeMappedFamily> mapped = new(StringComparer.OrdinalIgnoreCase);
    public Conductor NativeRuntime => this;
    public bool NativeFamiliesInitialized => mapped.Count == 13;
    public int NativeRegistrationCount { get; private set; }
    public int NativeConstructionCount { get; private set; }
    public int FabRegistrationCount { get; internal set; }
    public int FabObservationCount { get; internal set; }
    public Func<string, Type> TypeResolver { get; private set; }
    public Func<object, string, string, Signal, object, Signal, Signal> BusinessInvoker { get; private set; }
    public Func<object, object, Signal> ConfigurationHydrator { get; private set; }
    public FabRegistry Fab { get; private set; }
    public string BusinessModuleName { get; set; }
    public Func<object, IDictionary> MetadataConverter { get; set; }
    public Action<object, string, object> PlanMemberWriter { get; set; }
    public Func<object, string, object> PlanMemberReader { get; set; }
    public NativeMappedFamily GetFamily(string family) => family != null && mapped.TryGetValue(family, out var value) ? value : null;
    public void InitializeMappedAdapters(Func<string, Type> types, Func<object, string, string, Signal, object, Signal, Signal> invoke, Func<object, object, Signal> hydrate)
    {
        if (mapped.Count != 0) throw new InvalidOperationException("Mapped runtime already initialized.");
        TypeResolver = types ?? throw new ArgumentNullException(nameof(types)); BusinessInvoker = invoke; ConfigurationHydrator = hydrate;
        NativeMappedFamily[] families = { new MappedCondenserAdapter(this),new MappedStorageAdapter(this),new MappedConductionAdapter(this),new MappedConduitAdapter(this),new MappedDataAdapter(this),new MappedIntelligenceAdapter(this),new MappedNetworkAdapter(this),new MappedQuantumAdapter(this),new MappedQueueAdapter(this),new MappedSatelliteAdapter(this),new MappedSessionAdapter(this),new MappedTokenAdapter(this),new MappedUtilityAdapter(this) };
        var graph = (Graph)Graph.Start("MappedAdapters", Signal, true).Result;
        var root = SignalGraph.Signal.Start("Adapters", Signal); root.Pointer = graph;
        Memory.RegisterSignal("Adapters", root);
        foreach (var family in families) { mapped.Add(family.Family, family); graph.RegisterResultAsSignal("Mapped" + family.Family, family); NativeRegistrationCount++; }
        Fab = new FabRegistry(this);
        var condensers = new[] { "Fab", "Rest", "Process", "Format", "Merge", "Map", "Token", "Plan", "Signal", "Hydration", "Transform", "Conduit", "Memory", "Graph", "Conduction" };
        foreach (var name in condensers)
        {
            var instance = name == "Fab" ? (object)new SovereignTrust.Foundation.Classes.Adapters.Condenser.FabCondenser(this) : CreateBusiness(name + "Condenser", GetFamily("Condenser"));
            var registered = GetFamily("Condenser").RegisterAdapter(instance, name + "Condenser");
            if (registered.Failure()) throw new InvalidOperationException("Builtin condenser registration failed: " + name);
            NativeRegistrationCount++;
        }
        foreach (var name in new[] { "Dynamic", "System", "Memory", "Storage", "Environment", "Navigator", "Formatter", "Conduction", "Generator" })
        {
            var instance = CreateBusiness("Token_" + name, GetFamily("Token"));
            var registered = GetFamily("Token").RegisterAdapter(instance, name);
            if (registered.Failure()) throw new InvalidOperationException("Builtin token registration failed: " + name);
            NativeRegistrationCount++;
        }
    }
    object CreateBusiness(string name, NativeMappedFamily parent)
    {
        var type = TypeResolver(name) ?? throw new InvalidOperationException("Unknown business adapter type: " + name);
        var start = type.GetMethods(BindingFlags.Public | BindingFlags.Static).FirstOrDefault(method => method.Name == "Start" && method.GetParameters().Length == 2);
        if (start == null) throw new InvalidOperationException("Builtin business adapter has no two-context Start: " + name);
        var value = start.Invoke(null, new object[] { parent, this });
        if (value is Signal wrapped) { if (wrapped.Failure()) throw new InvalidOperationException("Business creation failed: " + name); value = wrapped.GetResult(true); }
        if (value == null) throw new InvalidOperationException("Business creation returned no instance: " + name);
        NativeConstructionCount++;
        return value;
    }
    internal object CreateLeaf(string fullType)
    {
        var type = TypeResolver(fullType) ?? throw new InvalidOperationException("Unknown adapter type: " + fullType);
        var instance = Activator.CreateInstance(type) ?? throw new InvalidOperationException("Adapter constructor returned no instance.");
        NativeConstructionCount++;
        return instance;
    }
    public Signal InvokeBusiness(object instance, string slot, string activity, Signal conduction, object plan, Signal item)
    {
        if (instance is IAdapterInvoker native) return native.Invoke(slot, activity, conduction, plan, item);
        if (BusinessInvoker == null) throw new InvalidOperationException("No selected PS business invocation bridge.");
        return BusinessInvoker(instance, slot, activity, conduction, plan, item);
    }
    public Signal InvokeFamily(string family, string slot, string activity, Signal conduction, object plan, Signal item)
    {
        var op = SignalGraph.Signal.Start("DispatchMapped:" + family, conduction);
        var owner = GetFamily(family);
        if (owner is not IAdapterInvoker invoker) return op.LogMessage("Critical", "Mapped family has no five-argument entry point: " + family);
        return invoker.Invoke(slot, activity, conduction, plan, item);
    }
}
