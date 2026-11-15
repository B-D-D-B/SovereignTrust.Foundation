using System;
using System.Collections.Generic;
using SignalGraph;
using SovereignTrust.Foundation.Classes.Conduction;

namespace SovereignTrust.Foundation.Wrappers.Adapters;

public static class AdapterDispatcher
{
    sealed class DelegateInvoker : IAdapterInvoker
    {
        internal object Owner;
        internal Func<string, string, Signal, object, Signal, Signal> Callback;
        public Signal Invoke(string slot, string activity, Signal conductionSignal, object plan, Signal itemSignal) => Callback(slot, activity, conductionSignal, plan, itemSignal);
    }
    static readonly HashSet<string> families = new(StringComparer.OrdinalIgnoreCase)
    { "Storage", "Condenser", "Token", "Conduction", "Data", "Network", "Intelligence", "Queue", "Satellite", "Session", "Utility" };
    static readonly HashSet<string> storageActivities = new(StringComparer.OrdinalIgnoreCase) { "Read", "Write", "Delete", "Exists", "List" };

    public static Signal Bind(Conductor conductor, string family, object owner, Func<string, string, Signal, object, Signal, Signal> callback)
    {
        var op = Signal.Start("BindAdapter:" + family, conductor?.Signal);
        if (conductor == null || owner == null || callback == null || !families.Contains(family ?? ""))
            return op.LogMessage("Critical", "A known family, conductor, owner and five-argument callback are required.");
        var existing = conductor.GetRegistration(family);
        if (existing != null)
        {
            var resolved = conductor.Resolve(family);
            if (resolved.Failure()) return resolved;
            if (resolved.Result is not DelegateInvoker previous || !ReferenceEquals(previous.Owner, owner))
                return op.LogMessage("Critical", "Mapped adapter identity changed for family: " + family);
            op.Result = previous;
            return op;
        }
        return conductor.Register(family, new AdapterDefinition { Family = family, Instance = new DelegateInvoker { Owner = owner, Callback = callback }, Lazy = true });
    }

    public static Signal Invoke(Conductor conductor, string family, string slot, string activity, Signal conductionSignal, object plan, Signal itemSignal, string routeFamily = null)
    {
        var op = Signal.Start("DispatchAdapter:" + family, conductionSignal);
        if (conductor == null || !families.Contains(family ?? "") || string.IsNullOrWhiteSpace(slot) || string.IsNullOrWhiteSpace(activity) || conductionSignal == null || itemSignal == null)
            return op.LogMessage("Critical", "A known family, slot, activity and canonical execution Signals are required.");
        if (routeFamily != null && !string.Equals(routeFamily, family, StringComparison.OrdinalIgnoreCase))
            return op.LogMessage("Critical", "Adapter route family mismatch.");
        if (conductor.NativeFamiliesInitialized) return conductor.InvokeFamily(family, slot, activity, conductionSignal, plan, itemSignal);
        if (family.Equals("Storage", StringComparison.OrdinalIgnoreCase) && !storageActivities.Contains(activity))
            return op.LogMessage("Critical", "Unsupported MappedStorageAdapter activity: '" + activity + "'.");
        var registration = conductor.GetRegistration(family);
        if (registration == null || !string.Equals(registration.Definition.Family, family, StringComparison.OrdinalIgnoreCase))
            return op.LogMessage("Critical", "Adapter registration family mismatch or missing registration.");
        var resolved = conductor.Resolve(family);
        if (op.MergeSignalAndVerifyFailure(resolved)) return op;
        if (resolved.Result is not IAdapterInvoker invoker)
            return op.LogMessage("Critical", "Resolved adapter does not implement the five-argument invocation contract.");
        try
        {
            conductor.DispatchCount++;
            var invoked = invoker.Invoke(slot, activity, conductionSignal, plan, itemSignal);
            if (invoked == null) return op.LogMessage("Critical", "Adapter returned no canonical Signal.");
            op.MergeSignal(invoked);
            if (invoked.HasResult()) op.Result = invoked.Result;
        }
        catch (Exception exception) { op.LogMessage("Critical", exception.Message, null, exception); }
        return op;
    }
}
