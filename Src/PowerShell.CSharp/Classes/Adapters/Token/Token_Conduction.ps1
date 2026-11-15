<#
Class: Token_Conduction
Purpose: Resolve conduction token values.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- Get: Resolve a token value from the requested path.
ActivityValidation: OnInvoke, BeforeDispatch
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
#>
class Token_Conduction {
    [SignalGraph.Signal]$Signal
    [SovereignTrust.Foundation.Classes.Conduction.Conductor]$Conductor
    [SovereignTrust.Foundation.Classes.Adapters.MappedTokenAdapter]$MappedAdapter
    [object]$Jacket

    Token_Conduction() {
    }

    static [Token_Conduction] Start([SovereignTrust.Foundation.Classes.Adapters.MappedTokenAdapter]$mappedAdapter, [SovereignTrust.Foundation.Classes.Conduction.Conductor]$conductor) {
        $instance = [Token_Conduction]::new()
        $instance.MappedAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [SignalGraph.Signal]::Start("GraphCondenser")
        return $instance
    }

    [SignalGraph.Signal] Construct([object]$dictionary) {
        $opSignal = [SignalGraph.Signal]::Start("Construct-EmbeddedFileSystem") | Select-Object -Last 1

        try {
            if ($null -eq $dictionary) {
                return $opSignal.LogCritical("Cannot construct EmbeddedFileSystem — provided dictionary is null.")
            }

            $this.Jacket = $dictionary
            $opSignal.LogInformation("EmbeddedFileSystem constructed successfully with provided jacket.")
        }
        catch {
            $opSignal.LogCritical("Error constructing EmbeddedFileSystem: $_", $null, $_.Exception)
        }

        return $opSignal
    }

[SignalGraph.Signal] Invoke([string]$Slot, [string]$Activity, $ConductionSignal, $Plan, $ItemSignal) {
        $opSignal = [SignalGraph.Signal]::Start("Token_Conduction.Invoke") | Select-Object -Last 1

        if ($Activity -notin @('Get')) {
            $opSignal.LogCritical("Unsupported Token_Conduction activity: '$Activity'.")
            return $opSignal
        }

    try {
            $Path = $Plan.Path
        $resultSignal = Invoke-TokenConduction -Conductor $this.Conductor -Path $Path -Plan $Plan | Select-Object -Last 1
        $opSignal.MergeSignal($resultSignal)

        if ($resultSignal.Success()) {
            $opSignal.SetResult($resultSignal.GetResult())
            $opSignal.LogInformation("✅ Token conduction path '$Path' resolved successfully.")
        } else {
            $opSignal.LogWarning("Token conduction path '$Path' failed to resolve.")
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Token_Conduction.Invoke: $($_.Exception.Message)", $null, $_.Exception)
    }

    return $opSignal
}
}
