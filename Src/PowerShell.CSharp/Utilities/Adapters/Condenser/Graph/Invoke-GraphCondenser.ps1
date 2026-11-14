function Invoke-GraphCondenser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Signal]$Signal
    )

    $opSignal = [Signal]::Start("Invoke-GraphCondenser", $Signal) | Select-Object -Last 1

    $plansSignal = Resolve-PathFromDictionary -Dictionary $Signal -Path "%.%.%.@.GraphPlans" | Select-Object -Last 1
    if ($opSignal.MergeSignalAndVerifyFailure($plansSignal)) {
        $opSignal.LogCritical("❌ No GraphPlans defined in Signal jacket.")
        return $opSignal
    }

    $plans = $plansSignal.GetResult()
    $planMap = @{}
    foreach ($plan in $plans) {
        $planMap[$plan.Name] = $plan
    }

    function Invoke-CondenserForPlan {
        param (
            [Signal]$Signal,
            [object]$Plan,
            [Signal]$ItemSignal,
            [string]$PlanWirePathPrefix = "%.@",
            [string]$OverrideCondenserType = $null
        )

        $condenserType = $Plan.CondenserType
        if ($OverrideCondenserType) {
            $condenserType = $OverrideCondenserType
        }

        switch ($condenserType) {
            "Token" {
                return Invoke-HydrateTokenCondenser -Signal $Signal -Plan $Plan -ItemSignal $ItemSignal -PlanWirePathPrefix $PlanWirePathPrefix | Select-Object -Last 1
            }
            "Grid" {
                return Invoke-GridCondenser -Signal $Signal -Plan $Plan -ItemSignal $ItemSignal -PlanWirePathPrefix $PlanWirePathPrefix | Select-Object -Last 1
            }
            "Hydration" {
                $opResult = Invoke-GraphHydrationCondenser -Signal $Signal -Plan $Plan -ItemSignal $ItemSignal -PlanWirePathPrefix $PlanWirePathPrefix | Select-Object -Last 1
                return $opResult
            }
            "Fab" {
                return Invoke-GraphFabCondenser -Signal $Signal -Plan $Plan -ItemSignal $ItemSignal -PlanWirePathPrefix $PlanWirePathPrefix | Select-Object -Last 1
            }
            "Conduction" {
                return Invoke-GraphConductionCondenser -Signal $Signal -Plan $Plan -ItemSignal $ItemSignal -PlanWirePathPrefix $PlanWirePathPrefix | Select-Object -Last 1
            }
            default {
                #            return Invoke-GridCondenser -Signal $Signal -Plan $Plan -ItemSignal $ItemSignal -PlanWirePathPrefix $PlanWirePathPrefix | Select-Object -Last 1
                $logSignal = [Signal]::Start("CondenserDispatch:$($Plan.Name)", $Signal) | Select-Object -Last 1
                $logSignal.LogWarning("Unsupported CondenserType '$($Plan.CondenserType)' for plan: $($Plan.Name)")
                return $logSignal
            }
        }
    }

    function Invoke-PlanAndDependents {
        param (
            [Signal]$Signal,
            [object]$Plan,
            [object]$Item,
            [object]$ParentPlan = $null
        )

        $planSignal = [Signal]::Start("GraphPlan:$($Plan.Name)", $Signal) | Select-Object -Last 1

        if ($Plan.CondenserType -eq "Fab") {
            $opSignal.LogInformation("🔄 Executing Token Condenser for plan: $($Plan.Name)")
        }

        if ($Plan.CondenserType -eq "Conduction") {
            $planSignal.LogInformation("🔄 Executing Token Condenser for plan: $($Plan.Name)")
        }

        if ($Plan.ForEachIn) {
            # Default to {0} if template missing/blank
            $template = if ([string]::IsNullOrWhiteSpace($Plan.ForEachInTemplate)) { '{0}' } else { $Plan.ForEachInTemplate }
            $isDefault = ($template -eq '{0}')

            # Enforce token
            if ($template -notmatch '\{0\}') {
                $planSignal.LogCritical("❌ ForEachInTemplate must contain '{0}'. Template: '$template'")
                return $planSignal
            }

            # Build and resolve path
            $path = [string]::Format($template, $Plan.ForEachIn)
            $arraySignal = Resolve-PathFromDictionary -Dictionary $Item -Path $path | Select-Object -Last 1

            if ($planSignal.MergeSignalAndVerifyFailure(@($arraySignal))) {
                $planSignal.LogWarning("Could not resolve array path for ForEachIn='$($Plan.ForEachIn)' → '$path'")
                return $planSignal
            }

            if ($isDefault) {
                $planSignal.LogInformation("✅ ForEachIn resolved: '$path'")
            }
            else {
                $planSignal.LogInformation("✅ ForEachIn resolved: '$path' (template: '$template')")
            }

            $set = $arraySignal.GetResult()

            if ($set -is [System.Collections.Specialized.OrderedDictionary]) {
                $set = $set.Values
            }

            foreach ($subItem in $set) {
                $injectionContextSignal = Resolve-GraphPlanInjectionContext -ParentPlan $ParentPlan -Plan $Plan -AllPlans $plans -Signal $Signal -ParentItem $Item -Dynamic $subItem | Select-Object -Last 1
                if ($planSignal.MergeSignalAndVerifyFailure($injectionContextSignal)) {
                    $planSignal.LogWarning("Could not resolve injection context for item in $($Plan.Name)")
                    continue
                }

                if ($subItem -is [Signal]) {
                    # Already a signal → use it directly
                    $subItemSignal = $subItem
                } else {
                    # Not a signal → wrap it
                    $subItemSignal = [Signal]::Start("Item:$($subItem.Name):Wrapper", $Item) | Select-Object -Last 1
                    $subItemSignal.SetResult($subItem) | Out-Null
                }

                if ($Plan.HydrationPlan) {
                    $condenserPreresult = Invoke-CondenserForPlan -Signal $Signal -Plan $Plan -ItemSignal $subItemSignal -PlanWirePathPrefix "%.@" -OverrideCondenserType "Hydration" | Select-Object -Last 1
                    if ($planSignal.MergeSignalAndVerifyFailure($condenserPreresult)) {
                        $planSignal.LogWarning("Graph plan [Hydration Pre-Step] failed for item in $($Plan.Name)")
                        continue
                    }
                }

                $condenserResult = Invoke-CondenserForPlan -Signal $Signal -Plan $Plan -ItemSignal $subItemSignal -PlanWirePathPrefix "%.@" | Select-Object -Last 1
                
                if ($planSignal.MergeSignalAndVerifyFailure($condenserResult)) {
                    $planSignal.LogWarning("Graph plan failed for item in $($Plan.Name)")
                    continue
                }

                if (-not $condenserResult.HasResult()) {
                    $planSignal.LogWarning("Condenser result is null for plan: $($Plan.Name)")
                }
                else {
                    $condenserResultSignal = $condenserResult.GetResult()
                    $injectionContext = $injectionContextSignal.GetResult()
                    if ($injectionContext.FullTargetPath) {
                        $injectSignal = Add-PathToDictionary -Dictionary $Item -Path $injectionContext.FullTargetPath -Value $condenserResultSignal | Select-Object -Last 1
                        if ($planSignal.MergeSignalAndVerifyFailure($injectSignal)) {
                            $planSignal.LogWarning("Failed to inject graph result for plan: $($Plan.Name)")
                            
                            continue
                        }
                        $planSignal.LogInformation("📍 Injected graph into '$($injectionContext.FullTargetPath)'")
                    }
                }

                $subItemJacketSignal = [Signal]::Start("Item:$($subItem.Name):Jacket", $Item) | Select-Object -Last 1
                $subItemJacketSignal.SetJacket($subItemSignal) | Out-Null

                $steps = $plans | Sort-Object Order | Where-Object { $_.DependsOn -eq $Plan.Name }
                foreach ($dependent in $steps) {
                    if ($null -ne $dependent.Condenser) {
                        $x = ""
                    }
                    else {
                        if ($dependent.CondenserType -eq "Fab") {
                            $plan = $Plan
                        }
                        if ($dependent.Name -eq "ConductionGraphPerRole") {
                            $plan = $Plan
                        }

                        $dependentResult = Invoke-PlanAndDependents -Signal $Signal -Plan $dependent -Item $subItemSignal -ParentPlan $Plan | Select-Object -Last 1
                        if ($planSignal.MergeSignalAndVerifyFailure($dependentResult)) {
                            $planSignal.LogWarning("Dependent '$($dependent.Name)' failed for item in $($Plan.Name)")
                            continue
                        }
                    }
                }
            
            }
        }
        else {
            if ($Plan.HydrationPlan) {
                $condenserPreresult = Invoke-CondenserForPlan -Signal $Signal -Plan $Plan -ItemSignal $Item -OverrideCondenserType "Hydration" | Select-Object -Last 1
                if ($planSignal.MergeSignalAndVerifyFailure($condenserPreresult)) {
                    $planSignal.LogWarning("Graph plan [Hydration Pre-Step] failed for item in $($Plan.Name)")
                    continue
                }
            }

            $condenserResultSignal = Invoke-CondenserForPlan -Signal $Signal -Plan $Plan -ItemSignal $Item | Select-Object -Last 1

            if (-not $condenserResultSignal) { return $planSignal }

            foreach ($dependent in $plans | Sort-Object Order | Where-Object { $_.DependsOn -eq $Plan.Name }) {
                Invoke-PlanAndDependents -Signal $Signal -Plan $dependent -Item $Item -ParentPlan $Plan | Out-Null
            }

            $planSignal.SetResult($condenserResultSignal.GetPointer())
        }

        return $planSignal
    }

    $rootItem = $Signal.GetJacket()
    foreach ($plan in $plans) {
        if (-not $plan.DependsOn) {
            Invoke-PlanAndDependents -Signal $Signal -Plan $plan -Item $rootItem -ParentPlan $null | Out-Null
        }
    }

    $finalGraph = Resolve-PathFromDictionary -Dictionary $Signal -Path "%" | Select-Object -Last 1

    $opSignal.SetResult($finalGraph.GetResult())
    $opSignal.LogInformation("✅ Completed all declared GraphPlans.")
    return $opSignal
}
