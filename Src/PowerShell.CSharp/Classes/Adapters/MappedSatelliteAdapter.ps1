<#
Class: MappedSatelliteAdapter
Purpose: Route a satellite slot through Invoke-MappedAdapterCore.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- EmitEntries: Emit telemetry entries and forward the stored { ItemsReceived, ItemsAccepted, Result } outcome, including on failure.
- EmitSignal: Emit a signal and forward the stored { ItemsReceived, ItemsAccepted, Result } outcome, including on failure.
- SendMessage: Count outbound JSON envelopes on the item graph, post the unchanged body, and return the raw REST receipt.
- HandleResponse: Provider-free normalization of Config.RawResponse and Config.ItemsSent into { ItemsReceived, ItemsAccepted, Result }; Result is exactly ItemsAccepted == ItemsSent regardless of errors. Store at Config.HandledResultKey before LogCritical per error; a count match with errors retains Result true in a failed Signal.
- EmitSignalFull: Mark entries to skip; the current branch does not emit them.
ActivityValidation: OnInvoke, BeforeProviderResolution
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
#>

class MappedSatelliteAdapter {
    [SignalGraph.Signal]$Signal

    MappedSatelliteAdapter() {
        # Use static Start() instead
    }

    static [SignalGraph.Signal] Start([object]$Conductor) {
        $opSignal = [SignalGraph.Signal]::Start("MappedSatelliteAdapter.Start") | Select-Object -Last 1

        if (-not $Conductor) {
            $opSignal.LogCritical("Null Conductor passed to MappedSatelliteAdapter.Start()")
            return $opSignal
        }

        try {
            $adapter = [SovereignTrust.Foundation.Classes.Adapters.MappedSatelliteAdapter]::new()
            $adapter.Signal = [SignalGraph.Signal]::Start("MappedSatelliteAdapter") | Select-Object -Last 1
            $adapter.Signal.SetJacket($Conductor)
            $adapter.Signal.SetReversePointer($Conductor)

            $graphSignal = [SignalGraph.Graph]::Start("MappedSatelliteAdapter", $adapter, $false)
            $adapter.Signal.SetPointer($graphSignal.GetResult())

            $opSignal.SetResult($adapter)
            $opSignal.LogInformation("✅ MappedSatelliteAdapter initialized.")
        }
        catch {
            $opSignal.LogCritical("💥 Exception in MappedSatelliteAdapter.Start(): $_", $null, $_.Exception)
        }

        return $opSignal
    }

    [SignalGraph.Signal] RegisterAdapter([object]$AdapterInstance, [string]$Key = "SatelliteService") {
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
        $opSignal = [SignalGraph.Signal]::Start("MappedSatelliteAdapter.Invoke:$Slot") | Select-Object -Last 1

        if ($Activity -notin @('EmitEntries', 'EmitSignal', 'SendMessage', 'HandleResponse', 'EmitSignalFull')) {
            $opSignal.LogCritical("Unsupported MappedSatelliteAdapter activity: '$Activity'.")
            return $opSignal
        }

        $resultSignal = Invoke-MappedAdapterCore -MappedAdapterSignal $this.Signal -ConductionSignal $ConductionSignal -Slot $Slot -Activity $Activity -Plan $Plan -ItemSignal $ItemSignal | Select-Object -Last 1

        $failed = $opSignal.MergeSignalAndVerifyFailure($resultSignal)
        if ($resultSignal.HasResult()) {
            $opSignal.SetResult($resultSignal.GetResult($true))
        }

        if ($failed) { return $opSignal }

        return $opSignal
    }
}
