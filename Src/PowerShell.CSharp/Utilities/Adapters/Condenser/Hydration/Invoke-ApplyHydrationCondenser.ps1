$TokenDispatch = @{
#    '*' = 'Global' # Replace with Conduction?
    '*' = 'Conduction' # Runs Conduction Plan
#    '@' = 'Token' # Token Replacements (String and Json documents)
    '@' = 'Map' # Token Replacements via Map (String and Json documents)
#    '+' = 'Json'  # Replace with Content?
    '+' = 'Content' 
    '-' = 'String' # Replace with?
    '~' = 'Navigator' # Xpath and json Lookups
    '#' = 'Map' # Variable replacements?
    '$' = 'Merge' # Merge documents (Json)
}

function Invoke-ApplyHydrationCondenser {
    param (
        [Parameter(Mandatory)] [Signal]$Signal,
        [Parameter(Mandatory)] [object]$Plan,
        [Parameter(Mandatory)] [object]$ItemSignal
    )

    $opSignal = [Signal]::Start("HydrationCondenser", $Signal) | Select-Object -Last 1

    
 #   $hydrationStyleSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "HydrationStyle" -SignalLevel "Information" | Select-Object -Last 1
 #   if ($hydrationStyleSignal.HasResult)
 #   {
 #       $HydrationStyle = $hydrationStyleSignal.GetResult()
 #   }

    # Assume there are no changes until a change occurs.
    $opSignal.SetResult($false)

    try {
        $hydrationPlanSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "HydrationPlan" -Default "^" | Select-Object -Last 1
        if (-not $opSignal.MergeSignalAndVerifySuccess(@($hydrationPlanSignal))) {
            $opSignal.LogInformation("ℹ️ No HydrationPlan specified, skipping hydration.")
            return $Signal
        }

        $hydrationPlan = $hydrationPlanSignal.GetResult()
    
        foreach ($step in ($hydrationPlan.ToCharArray())) {
            switch ($step) {
                '^' {
                    $oldResult = $Signal.GetResult() | ConvertTo-Json -Depth 99
                    do {
                        $prev = $oldResult
                        $stepSignal = Invoke-ApplyHydrationCondenser -Signal $Signal -Plan $Plan -ItemSignal $ItemSignal | Select-Object -Last 1
                        $oldResult = $stepSignal.GetResult() | ConvertTo-Json -Depth 99
                    } while ($prev -ne $oldResult)
                    $stepSignal
                }
                default {
                    if ($TokenDispatch.ContainsKey([string]$step)) {
                        $stepSignal = & Invoke-CondenserAdapter -Slot $TokenDispatch[[string]$step] -Signal $Signal -Plan $Plan -ItemSignal $ItemSignal | Select-Object -Last 1
                    } else {
                        $opSignal.LogWarning("Unknown hydration step: $step")
                        continue
                    }

                    $opSignal.SetResult($stepSignal.GetResult())
                }
            }

            if (-not $opSignal.MergeSignalAndVerifySuccess(@($stepSignal))) {
                $opSignal.LogCritical("Hydration step '$step' failed.")
                break
            }

#            if ($stepSignal.HasResult()) {
#                $opSignal.SetResult($stepSignal.GetResult())
#            }
        }
    }
    catch {
        $opSignal.LogCritical("🔥 HydrationCondenser exception: $_")
    }

    # TODO: Review this pattern, because we don't pass through the stepSignal on each pass, the original $ItemSignal.Result is the thing that gets updated.
#    $opSignal.SetResult($ItemSignal.GetJacket().GetResult())
    #$result = $ItemSignal.HasResult() ? $ItemSignal.GetResult() : $ItemSignal.GetJacket().GetResult()
    #$opSignal.SetResult($result)
    return $opSignal
}
