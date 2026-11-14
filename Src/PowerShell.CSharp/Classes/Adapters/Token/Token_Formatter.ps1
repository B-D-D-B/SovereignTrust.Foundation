<#
Class: Token_Formatter
Purpose: Resolve formatter token values.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- Get: Resolve a token value from the requested path.
ActivityValidation: OnInvoke, BeforeDispatch
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
#>
class Token_Formatter {
    [Signal]$Signal
    [Conductor]$Conductor
    [MappedTokenAdapter]$MappedAdapter
    [object]$Jacket

    Token_Formatter() {
    }

    static [Token_Formatter] Start([MappedTokenAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [Token_Formatter]::new()
        $instance.MappedAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("GraphCondenser")
        return $instance
    }

    [Signal] Construct([object]$dictionary) {
        $opSignal = [Signal]::Start("Construct-EmbeddedFileSystem") | Select-Object -Last 1

        try {
            if ($null -eq $dictionary) {
                return $opSignal.LogCritical("Cannot construct EmbeddedFileSystem — provided dictionary is null.")
            }

            $this.Jacket = $dictionary
            $opSignal.LogInformation("EmbeddedFileSystem constructed successfully with provided jacket.")
        }
        catch {
            $opSignal.LogCritical("Error constructing EmbeddedFileSystem: $_")
        }

        return $opSignal
    }

    [Signal] Invoke([string]$Slot, [string]$Activity, $ConductionSignal, $Plan, $ItemSignal) {
        $opSignal = [Signal]::Start("Token_Formatter.Invoke") | Select-Object -Last 1

        if ($Activity -notin @('Get')) {
            $opSignal.LogCritical("Unsupported Token_Formatter activity: '$Activity'.")
            return $opSignal
        }

        try {
            $Path = $Plan.Path
            $resultSignal = Invoke-TokenFormatter -Conductor $this.Conductor -Path $Path -Plan $Plan | Select-Object -Last 1
            $opSignal.MergeSignal($resultSignal)

            if ($resultSignal.Success()) {
                $opSignal.SetResult($resultSignal.GetResult())
                $opSignal.LogInformation("✅ Token formatter path '$Path' resolved successfully.")
            }
            else {
                $opSignal.LogWarning("Token formatter path '$Path' failed to resolve.")
            }
        }
        catch {
            $opSignal.LogCritical("🔥 Exception in Token_Formatter.Invoke: $($_.Exception.Message)", $null, $_)
        }

        return $opSignal
    }

}
