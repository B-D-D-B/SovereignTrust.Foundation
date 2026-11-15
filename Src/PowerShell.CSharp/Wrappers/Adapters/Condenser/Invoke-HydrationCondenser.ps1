function Invoke-HydrationCondenser {
    [CmdletBinding()]
    param (
        [SignalGraph.Signal]$Signal,
        [SignalGraph.Signal]$ItemSignal,
        [object]$Plan
    )

    # ░▒▓█ SIGNAL START █▓▒░
    $opSignal = [SignalGraph.Signal]::Start("Invoke-HydrationCondenser") | Select-Object -Last 1

    try {
        
        $consdenserPath = "%.*.#.Adapters.*.#.MappedCondenser.@.$.*.#.HydrationCondenser"
        $consdenserSignal = Resolve-PathFromDictionary -Dictionary ($Signal.GetControl($true)) -Path $consdenserPath -SignalLevel "Information" | Select-Object -Last 1

        $consdenser = $consdenserSignal.GetResult()
        while ($consdenser -is [SignalGraph.Signal])
        {
            $consdenser = $consdenser.GetResult()
        }
        
        if ($null -eq $Plan){
            $Plan = [PSCustomObject]@{
                HydrationPlan = "@"
            }
        }

        # ░▒▓█ Run the Conduction Condenser using the Config bits  █▓▒░
        $consdenserIvokeSignal = $consdenser.Invoke($null, 'Invoke', $Signal, $Plan , $ItemSignal) | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($consdenserIvokeSignal)) {
            $opSignal.LogCritical("Fab consdenser failed.")
            return $opSignal
        }
        else {
            $opSignal.SetResult($consdenserIvokeSignal.GetResult())
        }
    }
    catch {
        $opSignal.LogCritical("Exception during conduction condenser run: $($_.Exception.Message)", $null, $_.Exception)
    }

    return $opSignal

}
