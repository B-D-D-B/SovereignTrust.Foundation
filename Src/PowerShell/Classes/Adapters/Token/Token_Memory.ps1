<#
Class: Token_Memory
Purpose: Resolve memory token values.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- Get: Resolve a token value from the requested path.
ActivityValidation: OnInvoke, BeforeDispatch
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
#>
class Token_Memory {
    [Signal]$Signal
    [Conductor]$Conductor
    [MappedTokenAdapter]$MappedAdapter
    [object]$Jacket

    Token_Memory() {
    }

    static [Token_Memory] Start([MappedTokenAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [Token_Memory]::new()
        $instance.MappedAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("TokenMemory")
        return $instance
    }

    [Signal] Construct([object]$dictionary) {
        $opSignal = [Signal]::Start("Construct-TokenMemory") | Select-Object -Last 1

        try {
            if ($null -eq $dictionary) {
                return $opSignal.LogCritical("Cannot construct Token_Memory — provided dictionary is null.")
            }

            $this.Jacket = $dictionary
            $opSignal.LogInformation("Token_Memory constructed successfully with provided jacket.")
        }
        catch {
            $opSignal.LogCritical("🔥 Error constructing Token_Memory: $_")
        }

        return $opSignal
    }

    [Signal] Invoke([string]$Slot, [string]$Activity, $ConductionSignal, $Plan, $ItemSignal) {
        $opSignal = [Signal]::Start("Token_Memory.Invoke") | Select-Object -Last 1

        if ($Activity -notin @('Get')) {
            $opSignal.LogCritical("Unsupported Token_Memory activity: '$Activity'.")
            return $opSignal
        }

        try {
            $Path = $Plan.Path
            $resultSignal = Invoke-TokenMemory -Slot $Slot -Activity $Activity -Signal $ConductionSignal -ItemSignal $ItemSignal -Plan $Plan | Select-Object -Last 1
            $opSignal.MergeSignal($resultSignal)

            if ($resultSignal.Success() -and $resultSignal.HasResult()) {
                $opSignal.SetResult($resultSignal.GetResult())
                $opSignal.LogInformation("✅ Token Memory path '$Path' resolved successfully.")
            }
            else {
                $opSignal.LogWarning("Token Memory path '$Path' failed to resolve.")
            }
        }
        catch {
            $opSignal.LogCritical("🔥 Exception in Token_Memory.Invoke: $($_.Exception.Message)", $null, $_)
        }

        return $opSignal
    }
}
