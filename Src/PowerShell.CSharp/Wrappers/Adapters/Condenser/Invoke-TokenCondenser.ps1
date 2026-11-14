function Invoke-TokenCondenser {
    [CmdletBinding()]
    param (
        [Signal]$Signal,
        [Signal]$ItemSignal,
        [object]$Plan
    )

    # ░▒▓█ SIGNAL START █▓▒░
    $opSignal = [Signal]::Start("Invoke-TokenCondenser") | Select-Object -Last 1

    try {
        
        $consdenserPath = "%.*.#.Adapters.*.#.MappedCondenser.@.$.*.#.TokenCondenser"
        $consdenserSignal = Resolve-PathFromDictionary -Dictionary ($Signal.GetControl($true)) -Path $consdenserPath -SignalLevel "Information" | Select-Object -Last 1

        $consdenser = $consdenserSignal.GetResult()
        while ($consdenser -is [Signal])
        {
            $consdenser = $consdenser.GetResult()
        }
        
        if ($null -eq $Plan){
            $Plan = [PSCustomObject]@{
                HydrationPlan = "@"
            }
        }

        # ░▒▓█ Run the Conduction Condenser using the Config bits  █▓▒░
        $consdenserIvokeSignal = $consdenser.Invoke($null, 'Parse', $Signal, $Plan , $ItemSignal) | Select-Object -Last 1
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
