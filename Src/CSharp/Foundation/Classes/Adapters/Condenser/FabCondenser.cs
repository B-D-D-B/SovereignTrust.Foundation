using System;
using System.Collections;
using SignalGraph;
using SovereignTrust.Foundation.Classes.Conduction;
using SovereignTrust.Foundation.Wrappers.Adapters;

namespace SovereignTrust.Foundation.Classes.Adapters.Condenser;

public sealed class FabCondenser : IAdapterInvoker
{
    public Conductor Conductor { get; }
    public Signal Signal { get; }
    public FabCondenser(Conductor conductor) { Conductor = conductor; Signal = SignalGraph.Signal.Start("FabCondenser.Control"); }
    public Signal Invoke(string slot, string activity, Signal conduction, object plan, Signal item)
    {
        var op = SignalGraph.Signal.Start("FabCondenser.Invoke", item);
        try
        {
            var converted = plan == null ? Paths.NewDictionary() : Conductor.MetadataConverter(plan);
            var config = converted["Config"] as IDictionary;
            if (string.Equals(activity, "ObserveMappedAdapter", StringComparison.OrdinalIgnoreCase))
                return Conductor.Fab.Observe(Convert.ToString(config?["Kind"]), Convert.ToString(config?["Slot"]), Convert.ToString(config?["AbsentSlot"]), item);
            if (!string.Equals(activity, "Invoke", StringComparison.OrdinalIgnoreCase)) return op.LogMessage("Critical", "Unsupported FabCondenser activity: '" + activity + "'.");
            var source = Conductor.MetadataConverter(item?.Jacket);
            var loading = config?["AdapterLoading"] as IDictionary;
            bool lazy = !string.Equals(Convert.ToString(loading?["Mode"]), "Eager", StringComparison.OrdinalIgnoreCase);
            bool retry = loading?["RetryFailedResolution"] is bool value && value;
            return Conductor.Fab.Register(source, conduction, lazy, retry);
        }
        catch (Exception error) { return op.LogMessage("Critical", error.Message, null, error); }
    }
}
