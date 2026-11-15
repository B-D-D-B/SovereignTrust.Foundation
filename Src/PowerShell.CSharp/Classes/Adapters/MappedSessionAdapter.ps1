<#
Class: MappedSessionAdapter
Purpose: Route a session slot through Invoke-MappedAdapterCore.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- RequestOrRegister: Return an existing session or register a new one.
ActivityValidation: OnInvoke, BeforeProviderResolution
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
#>

class MappedSessionAdapter {
    [SignalGraph.Signal]$Signal

    MappedSessionAdapter() {
        # Use static Start() instead
    }

    static [SignalGraph.Signal] Start([object]$Conductor) {
        $opSignal = [SignalGraph.Signal]::Start("MappedSessionAdapter.Start") | Select-Object -Last 1

        if (-not $Conductor) {
            $opSignal.LogCritical("Null Conductor passed to MappedSessionAdapter.Start()")
            return $opSignal
        }

        try {
            $adapter = [SovereignTrust.Foundation.Classes.Adapters.MappedSessionAdapter]::new()
            $adapter.Signal = [SignalGraph.Signal]::Start("MappedSessionAdapter") | Select-Object -Last 1
            $adapter.Signal.SetJacket($Conductor)
            $adapter.Signal.SetReversePointer($Conductor)

            $graphSignal = [SignalGraph.Graph]::Start("MappedSessionAdapter", $adapter, $false)
            $adapter.Signal.SetPointer($graphSignal.GetResult())

            $opSignal.SetResult($adapter)
            $opSignal.LogInformation("✅ MappedSessionAdapter initialized.")
        }
        catch {
            $opSignal.LogCritical("💥 Exception in MappedSessionAdapter.Start(): $_", $null, $_.Exception)
        }

        return $opSignal
    }

    [SignalGraph.Signal] RegisterAdapter([object]$AdapterInstance, [string]$Key = "SessionService") {
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

        if ($Activity -notin @('RequestOrRegister')) {
            $opSignal.LogCritical("Unsupported MappedSessionAdapter activity: '$Activity'.")
            return $opSignal
        }

        $resultSignal = Invoke-MappedAdapterCore -MappedAdapterSignal $this.Signal -ConductionSignal $ConductionSignal -Slot $Slot -Activity $Activity -Plan $Plan -ItemSignal $ItemSignal | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)){
            return $opSignal
        }

        $opSignal.SetResult($resultSignal.GetResult($true))
        return $opSignal
    }
}
