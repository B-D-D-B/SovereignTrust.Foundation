function Invoke-FabCondenser {
    [CmdletBinding()]
    param (
        [Signal]$Signal,
        [Signal]$ItemSignal
    )

    # ░▒▓█ SIGNAL START █▓▒░
    $opSignal = [Signal]::Start("Invoke-FabCondenser") | Select-Object -Last 1

    try {
        $consdenserPath = "%.*.#.Adapters.*.#.MappedCondenser.@.$.*.#.FabCondenser"
        $consdenserSignal = Resolve-PathFromDictionary -Dictionary ($Signal.GetControl($true)) -Path $consdenserPath -SignalLevel "Information" | Select-Object -Last 1

        $consdenser = $consdenserSignal.GetResult()
        while ($consdenser -is [Signal])
        {
            $consdenser = $consdenser.GetResult()
        }
        
        # ░▒▓█ Run the Conduction Condenser using the Config bits  █▓▒░
        $consdenserIvokeSignal = $consdenser.Invoke($null, $Signal, $ItemSignal) | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($consdenserIvokeSignal)) {
            $opSignal.LogCritical("Fab consdenser failed.")
            return $opSignal
        }
        else {
            $opSignal.SetResult($consdenserIvokeSignal.GetResult())
        }
    }
    catch {
        $opSignal.LogCritical("Exception during conduction condenser run: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}