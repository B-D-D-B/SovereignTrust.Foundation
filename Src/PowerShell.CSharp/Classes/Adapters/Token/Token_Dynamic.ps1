<#
Class: Token_Dynamic
Purpose: Resolve dynamic token values.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- Get: Resolve a token value from the requested path.
ActivityValidation: OnInvoke, BeforeDispatch
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
#>
class Token_Dynamic {
    [SignalGraph.Signal]$Signal
    [SovereignTrust.Foundation.Classes.Conduction.Conductor]$Conductor
    [SovereignTrust.Foundation.Classes.Adapters.MappedTokenAdapter]$MappedAdapter
    [object]$Jacket

    Token_Dynamic() {
    }

    static [Token_Dynamic] Start([SovereignTrust.Foundation.Classes.Adapters.MappedTokenAdapter]$mappedAdapter, [SovereignTrust.Foundation.Classes.Conduction.Conductor]$conductor) {
        $instance = [Token_Dynamic]::new()
        $instance.MappedAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [SignalGraph.Signal]::Start("TokenMemory")
        return $instance
    }

    [SignalGraph.Signal] Construct([object]$dictionary) {
        $opSignal = [SignalGraph.Signal]::Start("Construct-TokenMemory") | Select-Object -Last 1

        try {
            if ($null -eq $dictionary) {
                return $opSignal.LogCritical("Cannot construct Token_Dynamic — provided dictionary is null.")
            }

            $this.Jacket = $dictionary
            $opSignal.LogInformation("Token_Dynamic constructed successfully with provided jacket.")
        }
        catch {
            $opSignal.LogCritical("🔥 Error constructing Token_Dynamic: $_", $null, $_.Exception)
        }

        return $opSignal
    }

    [SignalGraph.Signal] Invoke([string]$Slot, [string]$Activity, $ConductionSignal, $Plan, $ItemSignal) {
        $opSignal = [SignalGraph.Signal]::Start("Token_Dynamic.Invoke") | Select-Object -Last 1

        if ($Activity -notin @('Get')) {
            $opSignal.LogCritical("Unsupported Token_Dynamic activity: '$Activity'.")
            return $opSignal
        }

    try {
            $Path = $Plan.Path
        $resultSignal = Invoke-TokenDynamic -MappedAdapter $this.MappedAdapter -Slot $Slot -Activity $Activity -Signal $ConductionSignal -ItemSignal $ItemSignal -Plan $Plan | Select-Object -Last 1
        $opSignal.MergeSignal($resultSignal)

        if ($resultSignal.Success() -and $resultSignal.HasResult()) {
            $opSignal.SetResult($resultSignal.GetResult())
            $opSignal.LogInformation("✅ Token Dynamic path '$Path' resolved successfully.")
        } else {
            $opSignal.LogWarning("Token Dynamic path '$Path' failed to resolve.")
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Token_Dynamic.Invoke: $($_.Exception.Message)", $null, $_.Exception)
    }

    return $opSignal
}
}
