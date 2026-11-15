using SignalGraph;

namespace SovereignTrust.Foundation.Wrappers.Adapters;

public interface IAdapterInvoker
{
    Signal Invoke(string slot, string activity, Signal conductionSignal, object plan, Signal itemSignal);
}
