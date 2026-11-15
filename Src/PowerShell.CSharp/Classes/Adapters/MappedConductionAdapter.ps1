<#
Class: MappedConductionAdapter
Purpose: Route a conduction slot through Invoke-MappedAdapterCore.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- Invoke: Execute a conduction plan.
- Run: Run a conduction plan.
- ST: Execute a SovereignTrust conduction plan.
ActivityValidation: OnInvoke, BeforeProviderResolution
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
#>

class MappedConductionAdapter {
    [SignalGraph.Signal]$Signal

    MappedConductionAdapter() {
        # Use static Start() instead
    }

    static [SignalGraph.Signal] Start([object]$Conductor) {
        $opSignal = [SignalGraph.Signal]::Start("MappedConductionAdapter.Start") | Select-Object -Last 1

        if (-not $Conductor) {
            $opSignal.LogCritical("Null Conductor passed to MappedConductionAdapter.Start()")
            return $opSignal
        }

        try {
            $adapter = [SovereignTrust.Foundation.Classes.Adapters.MappedConductionAdapter]::new()
            $adapter.Signal = [SignalGraph.Signal]::Start("MappedConductionAdapter") | Select-Object -Last 1
            $adapter.Signal.SetJacket($Conductor)
            $adapter.Signal.SetReversePointer($Conductor)

            $graphSignal = [SignalGraph.Graph]::Start("MappedConductionAdapter", $adapter, $false)
            $adapter.Signal.SetPointer($graphSignal.GetResult())

            $opSignal.SetResult($adapter)
            $opSignal.LogInformation("✅ MappedConductionAdapter initialized.")
        }
        catch {
            $opSignal.LogCritical("💥 Exception in MappedConductionAdapter.Start(): $_", $null, $_.Exception)
        }

        return $opSignal
    }

    [SignalGraph.Signal] RegisterAdapter([object]$AdapterInstance, [string]$Key = "ConductionService") {
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
        $opSignal = [SignalGraph.Signal]::Start("MappedConductionAdapter.Invoke:$Slot") | Select-Object -Last 1

        if ($Activity -notin @('Invoke', 'Run', 'ST')) {
            $opSignal.LogCritical("Unsupported MappedConductionAdapter activity: '$Activity'.")
            return $opSignal
        }

        $resultSignal = Invoke-MappedAdapterCore -MappedAdapterSignal $this.Signal -ConductionSignal $ConductionSignal -Slot $Slot -Activity $Activity -Plan $Plan -ItemSignal $ItemSignal | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)){
            return $opSignal
        }

        $opSignal.GetResult($resultSignal.GetResult($true))
        return $opSignal
    }
}
