<#
Class: Token_System
Purpose: Resolve system token values.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- Get: Resolve a token value from the requested path.
ActivityValidation: OnInvoke, BeforeDispatch
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
#>
class Token_System {
    [Signal]$Signal
    [Conductor]$Conductor
    [MappedTokenAdapter]$MappedAdapter
    [object]$Jacket

    Token_System() {
    }

    static [Token_System] Start([MappedTokenAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [Token_System]::new()
        $instance.MappedAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("TokenSystem")
        return $instance
    }

    [Signal] Construct([object]$dictionary) {
        $opSignal = [Signal]::Start("Construct-TokenSystem") | Select-Object -Last 1

        try {
            if ($null -eq $dictionary) {
                return $opSignal.LogCritical("Cannot construct Token_System — provided dictionary is null.")
            }

            $this.Jacket = $dictionary
            $opSignal.LogInformation("Token_System constructed successfully with provided jacket.")
        }
        catch {
            $opSignal.LogCritical("🔥 Error constructing Token_System: $_")
        }

        return $opSignal
    }

    [Signal] Invoke([string]$Slot, [string]$Activity, $ConductionSignal, $Plan, $ItemSignal) {
        $opSignal = [Signal]::Start("Token_System.Invoke") | Select-Object -Last 1

        if ($Activity -notin @('Get')) {
            $opSignal.LogCritical("Unsupported Token_System activity: '$Activity'.")
            return $opSignal
        }

        try {
            $Path = $Plan.Path
            $resultSignal = Invoke-TokenSystem -Conductor $this.Conductor -Path $Path -Plan $Plan | Select-Object -Last 1
            $opSignal.MergeSignal($resultSignal)

            if ($resultSignal.Success()) {
                $opSignal.SetResult($resultSignal.GetResult())
                $opSignal.LogInformation("✅ Token System path '$Path' resolved successfully.")
            }
            else {
                $opSignal.LogWarning("Token System path '$Path' failed to resolve.")
            }
        }
        catch {
            $opSignal.LogCritical("🔥 Exception in Token_System.Invoke: $($_.Exception.Message)", $null, $_)
        }

        return $opSignal
    }
}
