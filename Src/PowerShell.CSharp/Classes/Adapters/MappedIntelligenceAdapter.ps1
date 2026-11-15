<#
Class: MappedIntelligenceAdapter
Purpose: Route an intelligence slot through Invoke-MappedAdapterCore.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- SendMessage: Send a request to an intelligence service.
- HandleMessage: Resolve and optionally format a message.
ActivityValidation: OnInvoke, BeforeProviderResolution
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
ActivityForwarding: Canonical
#>

class MappedIntelligenceAdapter {
    [SignalGraph.Signal]$Signal

    MappedIntelligenceAdapter() {
        # Use static Start() instead
    }

    static [SignalGraph.Signal] Start([object]$Conductor) {
        $opSignal = [SignalGraph.Signal]::Start("MappedIntelligenceAdapter.Start") | Select-Object -Last 1

        if (-not $Conductor) {
            $opSignal.LogCritical("Null Conductor passed to MappedIntelligenceAdapter.Start()")
            return $opSignal
        }

        try {
            $adapter = [SovereignTrust.Foundation.Classes.Adapters.MappedIntelligenceAdapter]::new()
            $adapter.Signal = [SignalGraph.Signal]::Start("MappedIntelligenceAdapter") | Select-Object -Last 1
            $adapter.Signal.SetJacket($Conductor)
            $adapter.Signal.SetReversePointer($Conductor)

            $graphSignal = [SignalGraph.Graph]::Start("MappedIntelligenceAdapter", $adapter, $false)
            $adapter.Signal.SetPointer($graphSignal.GetResult())

            $opSignal.SetResult($adapter)
            $opSignal.LogInformation("✅ MappedIntelligenceAdapter initialized.")
        }
        catch {
            $opSignal.LogCritical("💥 Exception in MappedIntelligenceAdapter.Start(): $_", $null, $_.Exception)
        }

        return $opSignal
    }

    [SignalGraph.Signal] RegisterAdapter([object]$AdapterInstance, [string]$Key = "IntelligenceService") {
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
        }
        else {
            $opSignal.LogWarning("Failed to register adapter at key: '$Key'")
        }

        $this.Signal.MergeSignal($opSignal)
        return $opSignal
    }

    [SignalGraph.Signal] Invoke([string]$Slot, [string]$Activity, [SignalGraph.Signal]$ConductionSignal, [object]$Plan, [SignalGraph.Signal]$ItemSignal) {
        $opSignal = [SignalGraph.Signal]::Start("MappedIntelligenceAdapter.Invoke:$Slot") | Select-Object -Last 1

        $allowedActivities = @('SendMessage', 'HandleMessage')
        if ($Activity -notin $allowedActivities) {
            $opSignal.LogCritical("Unsupported MappedIntelligenceAdapter activity: '$Activity'.")
            return $opSignal
        }
        foreach ($allowedActivity in $allowedActivities) {
            if ($Activity -eq $allowedActivity) { $Activity = $allowedActivity; break }
        }

        $resultSignal = Invoke-MappedAdapterCore -MappedAdapterSignal $this.Signal -ConductionSignal $ConductionSignal -Slot $Slot -Activity $Activity -Plan $Plan -ItemSignal $ItemSignal | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)) {
            return $opSignal
        }

        if ($resultSignal.HasResult()) {
            $opSignal.SetResult($resultSignal.GetResult($true))
        }

        return $opSignal
    }
}
