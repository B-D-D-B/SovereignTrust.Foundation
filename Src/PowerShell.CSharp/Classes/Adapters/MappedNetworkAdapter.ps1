<#
Class: MappedNetworkAdapter
Purpose: Route a network slot through Invoke-MappedAdapterCore.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- SendFile: Send a file through a network service.
- SendMessage: Send a message.
- ReadBatch: Read a batch of messages.
- HandleMessage: Process message content.
ActivityValidation: OnInvoke, BeforeProviderResolution
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
The three-argument Invoke overload has no Activity parameter.
#>

class MappedNetworkAdapter {
    [SignalGraph.Signal]$Signal

    MappedNetworkAdapter() {
        # Use static Start() instead
    }

    static [SignalGraph.Signal] Start([object]$Conductor) {
        $opSignal = [SignalGraph.Signal]::Start("MappedNetworkAdapter.Start") | Select-Object -Last 1

        if (-not $Conductor) {
            $opSignal.LogCritical("Null Conductor passed to MappedNetworkAdapter.Start()")
            return $opSignal
        }

        try {
            $adapter = [SovereignTrust.Foundation.Classes.Adapters.MappedNetworkAdapter]::new()
            $adapter.Signal = [SignalGraph.Signal]::Start("MappedNetworkAdapter") | Select-Object -Last 1
            $adapter.Signal.SetJacket($Conductor)
            $adapter.Signal.SetReversePointer($Conductor)

            $graphSignal = [SignalGraph.Graph]::Start("MappedNetworkAdapter", $adapter, $false)
            $adapter.Signal.SetPointer($graphSignal.GetResult())

            $opSignal.SetResult($adapter)
            $opSignal.LogInformation("✅ MappedNetworkAdapter initialized.")
        }
        catch {
            $opSignal.LogCritical("💥 Exception in MappedNetworkAdapter.Start(): $_", $null, $_.Exception)
        }

        return $opSignal
    }

    [SignalGraph.Signal] RegisterAdapter([object]$AdapterInstance, [string]$Key = "NetworkService") {
        $opSignal = [SignalGraph.Signal]::Start("RegisterMappedAdapter:$Key") | Select-Object -Last 1
        if ($AdapterInstance -isnot [SignalGraph.Signal]) {
            $adapterSignal = [SignalGraph.Signal]::Start("Adapter:$Key") | Select-Object -Last 1
            $adapterSignal.SetResult($AdapterInstance)
        }
        else {
            $adapterSignal = $AdapterInstance
        }

        $AddMappedAdapterSignal = Add-PathToDictionary -Dictionary $AdapterInstance -Path "MappedAdapter" -Value $this | Select-Object -Last 1
        $graph = $this.Signal.GetPointer()
        $registerSignal = $graph.RegisterSignal($Key, $adapterSignal)
        $opSignal.MergeSignal($registerSignal)

        if ($registerSignal.Success()) {
            $opSignal.LogInformation("✅ Registered adapter at key: '$Key'")
        } else {
            $opSignal.LogWarning("Failed to register adapter at key: '$Key'")
        }

        $this.Signal.MergeSignal($opSignal)
        return $opSignal
    }

    [SignalGraph.Signal] Invoke([string]$Slot, [string]$Activity, [SignalGraph.Signal]$ConductionSignal, [object]$Plan, [SignalGraph.Signal]$ItemSignal) {
        $opSignal = [SignalGraph.Signal]::Start("MappedDataAdapter.Invoke:$Slot") | Select-Object -Last 1

        if ($Activity -notin @('SendFile', 'SendMessage', 'ReadBatch', 'HandleMessage')) {
            $opSignal.LogCritical("Unsupported MappedNetworkAdapter activity: '$Activity'.")
            return $opSignal
        }

        $resultSignal = Invoke-MappedAdapterCore -MappedAdapterSignal $this.Signal -ConductionSignal $ConductionSignal -Slot $Slot -Activity $Activity -Plan $Plan -ItemSignal $ItemSignal | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)){
            return $opSignal
        }

        $opSignal.SetResult($resultSignal.GetResult($true))
        return $opSignal
    }

    [SignalGraph.Signal] Invoke([string]$Slot, [object]$Context, [object]$Plan) {
        $opSignal = [SignalGraph.Signal]::Start("MappedNetworkAdapter.Invoke:$Slot") | Select-Object -Last 1

        $conductor = $this.Signal.GetJacket()
        $opSignal = Invoke-NetworkAdapter -MappedAdapterSignal $this.Signal -NetworkSignal $Context -Slot $Slot | Select-Object -Last 1

        return $opSignal
    }
}
