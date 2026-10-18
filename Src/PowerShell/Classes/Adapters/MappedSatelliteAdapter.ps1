<#
Class: MappedSatelliteAdapter
Purpose: Route a satellite slot through Invoke-MappedAdapterCore.
Activities: Provider-defined; the wrapper forwards Activity.
- AzureApplicationInsights: EmitEntries and EmitSignal (resolve configured
  plan tokens and run an emission conduction plan), SendMessage (post a
  telemetry message through REST), EmitSignalFull (mark entries Skip only;
  it does not dispatch an emission plan).
#>

class MappedSatelliteAdapter {
    [Signal]$Signal

    MappedSatelliteAdapter() {
        # Use static Start() instead
    }

    static [Signal] Start([object]$Conductor) {
        $opSignal = [Signal]::Start("MappedSatelliteAdapter.Start") | Select-Object -Last 1

        if (-not $Conductor) {
            $opSignal.LogCritical("Null Conductor passed to MappedSatelliteAdapter.Start()")
            return $opSignal
        }

        try {
            $adapter = [MappedSatelliteAdapter]::new()
            $adapter.Signal = [Signal]::Start("MappedSatelliteAdapter") | Select-Object -Last 1
            $adapter.Signal.SetJacket($Conductor)
            $adapter.Signal.SetReversePointer($Conductor)

            $graphSignal = [Graph]::Start("MappedSatelliteAdapter", $adapter, $false)
            $adapter.Signal.SetPointer($graphSignal.GetResult())

            $opSignal.SetResult($adapter)
            $opSignal.LogInformation("✅ MappedSatelliteAdapter initialized.")
        }
        catch {
            $opSignal.LogCritical("💥 Exception in MappedSatelliteAdapter.Start(): $_", $null, $_)
        }

        return $opSignal
    }

    [Signal] RegisterAdapter([object]$AdapterInstance, [string]$Key = "SatelliteService") {
        $opSignal = [Signal]::Start("RegisterMappedAdapter:$Key") | Select-Object -Last 1
        if ($AdapterInstance -isnot [Signal]) {
            $adapterSignal = [Signal]::Start("Adapter:$Key") | Select-Object -Last 1
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

    [Signal] Invoke([string]$Slot, [string]$Activity, [Signal]$ConductionSignal, [object]$Plan, [Signal]$ItemSignal) {
        $opSignal = [Signal]::Start("MappedSatelliteAdapter.Invoke:$Slot") | Select-Object -Last 1

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
