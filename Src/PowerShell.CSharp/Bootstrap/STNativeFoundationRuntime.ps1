# Explicit hybrid provider boundary: native registry/dispatch owns the call;
# the selected PS adapter retains its business logic and canonical SG objects.
function Invoke-STNativeMappedAdapter {
    param($MappedAdapter,[string]$Family,[string]$Slot,[string]$Activity,[SignalGraph.Signal]$ConductionSignal,$Plan,[SignalGraph.Signal]$ItemSignal)
    $owner=$MappedAdapter.Signal.GetJacket()
    $native=$owner.NativeRuntime
    if($null -eq $native){throw 'ST_NATIVE_RUNTIME: selected mapped adapter has no native conductor'}
    if($native.NativeFamiliesInitialized){return [SovereignTrust.Foundation.Wrappers.Adapters.AdapterDispatcher]::Invoke($native,$Family,$Slot,$Activity,$ConductionSignal,$Plan,$ItemSignal,$Family)}
    $callbackScript={
        param($slot,$activity,$conduction,$plan,$item)
        $MappedAdapter.Invoke($slot,$activity,$conduction,$plan,$item)|Select-Object -Last 1
    }.GetNewClosure()
    $callback=[System.Func[string,string,SignalGraph.Signal,object,SignalGraph.Signal,SignalGraph.Signal]]$callbackScript
    $bound=[SovereignTrust.Foundation.Wrappers.Adapters.AdapterDispatcher]::Bind($native,$Family,$MappedAdapter,$callback)
    if($bound.Failure()){return $bound}
    [SovereignTrust.Foundation.Wrappers.Adapters.AdapterDispatcher]::Invoke($native,$Family,$Slot,$Activity,$ConductionSignal,$Plan,$ItemSignal,$Family)
}
