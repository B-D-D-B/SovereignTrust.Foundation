<#
Class: Token_Environment
Purpose: Resolve environment token values.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- Get: Resolve a token value from the requested path.
ActivityValidation: OnInvoke, BeforeDispatch
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
#>
class Token_Environment {
    [Signal]$Signal
    [Conductor]$Conductor
    [MappedTokenAdapter]$MappedAdapter
    [object]$Jacket

    Token_Environment() {
    }

    static [Token_Environment] Start([MappedTokenAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [Token_Environment]::new()
        $instance.MappedAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("TokenEnvironment")
        return $instance
    }

    [Signal] Construct([object]$dictionary) {
        $opSignal = [Signal]::Start("Construct-TokenEnvironment") | Select-Object -Last 1

        try {
            if ($null -eq $dictionary) {
                return $opSignal.LogCritical("Cannot construct Token_Environment — provided dictionary is null.")
            }

            $this.Jacket = $dictionary
            $opSignal.LogInformation("Token_Environment constructed successfully with provided jacket.")
        }
        catch {
            $opSignal.LogCritical("🔥 Error constructing Token_Environment: $_")
        }

        return $opSignal
    }

    [Signal] Invoke([string]$Slot, [string]$Activity, $ConductionSignal, $Plan, $ItemSignal) {
        $opSignal = [Signal]::Start("Token_Environment.Invoke") | Select-Object -Last 1

        if ($Activity -notin @('Get')) {
            $opSignal.LogCritical("Unsupported Token_Environment activity: '$Activity'.")
            return $opSignal
        }

    try {
            $Path = $Plan.Path
        $resultSignal = Invoke-TokenEnvironment -Conductor $this.Conductor -Path $Path -Plan $Plan | Select-Object -Last 1
        $opSignal.MergeSignal($resultSignal)

        if ($resultSignal.Success()) {
            $opSignal.SetResult($resultSignal.GetResult())
            $opSignal.LogInformation("✅ Token environment path '$Path' resolved successfully.")
        } else {
            $opSignal.LogWarning("Token environment path '$Path' failed to resolve.")
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Token_Environment.Invoke: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}
}
