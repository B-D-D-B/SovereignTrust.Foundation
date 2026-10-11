class Token_Dynamic {
    [Signal]$Signal
    [Conductor]$Conductor
    [MappedTokenAdapter]$MappedAdapter
    [object]$Jacket

    Token_Dynamic() {
    }

    static [Token_Dynamic] Start([MappedTokenAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [Token_Dynamic]::new()
        $instance.MappedAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("TokenMemory")
        return $instance
    }

    [Signal] Construct([object]$dictionary) {
        $opSignal = [Signal]::Start("Construct-TokenMemory") | Select-Object -Last 1

        try {
            if ($null -eq $dictionary) {
                return $opSignal.LogCritical("Cannot construct Token_Dynamic — provided dictionary is null.")
            }

            $this.Jacket = $dictionary
            $opSignal.LogInformation("Token_Dynamic constructed successfully with provided jacket.")
        }
        catch {
            $opSignal.LogCritical("🔥 Error constructing Token_Dynamic: $_", $null, $_)
        }

        return $opSignal
    }

    [Signal] Invoke([string]$Slot, [string]$Activity, $ConductionSignal, $Plan, $ItemSignal) {
    $opSignal = [Signal]::Start("Token_Dynamic.Invoke") | Select-Object -Last 1

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
        $opSignal.LogCritical("🔥 Exception in Token_Dynamic.Invoke: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}
}
