# =============================================================================
# 🔐 PlanCondenser (Graph Context + XPath Token Resolution)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists / BDDB
#  Authors: Shadow PhanTom ☠️🧁👾️/🤖 • Neural Alchemist ⚗️☣️🐲 • Last Updated: 05/20/2025
# =============================================================================
# Uses XPath-based token lookup with imported graph documents to resolve runtime
# variables within sovereign templates. This condenser class is central to hydration
# flows, token graph processing, and context-sensitive publishing.
# =============================================================================

class PlanCondenser {
    [Conductor]$Conductor
    [MappedCondenserAdapter]$MappedCondenserAdapter
    [Signal]$Signal

    PlanCondenser() {
        # Empty constructor — use Start()
    }

    static [PlanCondenser] Start([MappedCondenserAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [PlanCondenser]::new()
        $instance.MappedCondenserAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("PlanCondenser.Control") | Select-Object -Last 1
        return $instance
    }

    [Signal] ResolveInsertPhaseSteps(
        [Signal]$ParentSignal,
        $ConductionSignal,
        $Plan,
        $ItemSignal
    ) {
        $opSignal = [Signal]::Start("PlanCondenser.ResolveInsertPhaseSteps", $ParentSignal) | Select-Object -Last 1

        $iteration = $Plan.Config.Iteration ?? 0
        if ($Plan.Config.PreventReclone -and $iteration -gt 0)
        {
            if ($iteration -gt 1)
            {
                $opSignal.LogInformation("Skip Repeat Cloning")
                return $opSignal
            }
        }

        # Get the steps to inject
        $phaseStepsSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $Plan.Path | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($phaseStepsSignal)) { return $opSignal }

        # Get the current phase steps
#        $planStepsSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Phase.Steps" | Select-Object -Last 1
#        if ($opSignal.MergeSignalAndVerifyFailure($planStepsSignal)) { return $opSignal }

        $phaseSteps = $phaseStepsSignal.GetResult()
#        $planSteps = $planStepsSignal.GetResult()
        $currentPlanName = $Plan.Name

        $breakSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Break" -Default $false | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($breakSignal)) { return $opSignal }

        if ($breakSignal.GetResult()) {
            $check = ""
        }

        # Clone steps so they can be reused safely
        $cloneSignal = Resolve-ClonePlan -Plan $phaseSteps | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($cloneSignal)) { return $opSignal }

        $phaseSteps = $cloneSignal.GetResult()

        $hydrationPlan = [PSCustomObject]@{
            Path          = "%.@"
            HydrationPlan = "@"
            HydrationStyle = "Standard"
            Config        = $Plan.Config
        }

        # Hydrate the injected steps
        $subItemSignal = [Signal]::Start("PlanCondenser.ResolveInsertPhaseSteps", $ItemSignal) | Select-Object -Last 1
        $subItemSignal.SetJacketResult($phaseSteps)

        # Pass through the Pointer so the Hydration process has it available to resolve values.
        $subItemSignal.SetPointer($ItemSignal.GetPointer())

        if ($Plan.Name -like "*ManageLineage"){
            $a = ""
        }

        $stepHydrateResultSignal = Invoke-CondenserAdapter -Slot "Hydration" -Plan $hydrationPlan -Signal $ConductionSignal -ItemSignal $subItemSignal | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($stepHydrateResultSignal)) { return $opSignal }

        $phaseSteps = $stepHydrateResultSignal.GetResult()

        $skipRenameSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.SkipRename" -Default $false | Select-Object -Last 1
        if (-not $skipRenameSignal.GetResult()) {
            foreach ($step in @($phaseSteps)) {
                $step.Name = "$($currentPlanName)_$($step.Name)"
            }
        }

        <#
        $newSteps = @()
        foreach ($step in @($planSteps)) {
            $newSteps += $step
            if ($step.Name -eq $currentPlanName) {
                $newSteps += $phaseSteps
            }
        }
        #>

        $opSignal.SetResult($phaseSteps)
        return $opSignal
    }

    [Signal] Invoke([string]$Slot, [string]$Activity, $ConductionSignal, $Plan, $ItemSignal) {
        $opSignal = [Signal]::Start("PlanCondenser.Invoke", $ItemSignal) | Select-Object -Last 1

        $PlanPathSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Path" | Select-Object -Last 1
        $DefaultPath = $PlanPathSignal.GetResult()

        if ($Activity) {
            switch ($Activity) {
                "IteratePhase" {
                    $iterationArraySignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.IterationArray" | Select-Object -Last 1
                    $iterationNameSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.IterationName" -Default "Iteration" | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure(@($iterationArraySignal, $iterationNameSignal))) {
                        return $opSignal
                    }

                    $iterationArray = @($iterationArraySignal.GetResult())
                    $iterationName = [string]$iterationNameSignal.GetResult()
                    if ($iterationArray.Count -eq 0) {
                        break
                    }

                    $threading = $Plan.Config.Threading
                    $warmup = 0
                    if ($null -ne $threading -and $null -ne $threading.Warmup) {
                        try {
                            $warmup = [int]$threading.Warmup
                        }
                        catch {
                            $null = $opSignal.LogCritical("Plan.Config.Threading.Warmup must be an integer.")
                            return $opSignal
                        }
                    }
                    if ($warmup -lt -1) {
                        $null = $opSignal.LogCritical("Plan.Config.Threading.Warmup cannot be less than -1.")
                        return $opSignal
                    }

                    $runtimeGraph = $ConductionSignal.GetPointer()
                    $environmentDetails = $null
                    if ($runtimeGraph -is [Graph] -and $runtimeGraph.Grid.Contains('EnvironmentDetails')) {
                        $environmentDetails = $runtimeGraph.Grid['EnvironmentDetails'].GetResult()
                    }

                    $supportParallelism = $false
                    $maxThreads = 1
                    try {
                        if ($null -ne $environmentDetails -and $null -ne $environmentDetails.Config) {
                            $supportParallelism = [bool]$environmentDetails.Config.SupportParallelism
                            if ($null -ne $environmentDetails.Config.MaxParallelism) {
                                $maxThreads = [Math]::Max(1, [int]$environmentDetails.Config.MaxParallelism)
                            }
                        }
                        if ($null -ne $threading -and $null -ne $threading.MaxThreads) {
                            $maxThreads = [Math]::Max(1, [int]$threading.MaxThreads)
                        }
                    }
                    catch {
                        $null = $opSignal.LogCritical("Threading MaxThreads and environment MaxParallelism must be integers.")
                        return $opSignal
                    }

                    $reuseItemSignalGrid = $false
                    if ($null -ne $threading -and $null -ne $threading.ReuseItemSignalGrid) {
                        $reuseItemSignalGrid = [bool]$threading.ReuseItemSignalGrid
                    }

                    $debugInline = $false
                    if ($null -ne $threading -and $null -ne $threading.DebugInline) {
                        $debugInline = [bool]$threading.DebugInline
                    }

                    $warmupCount = if ($warmup -eq -1) {
                        $iterationArray.Count
                    }
                    else {
                        [Math]::Min([Math]::Max(0, $warmup), $iterationArray.Count)
                    }

                    $debugWorkItemIndex = $warmupCount
                    if ($null -ne $threading -and $null -ne $threading.DebugWorkItemIndex) {
                        try {
                            $debugWorkItemIndex = [int]$threading.DebugWorkItemIndex
                        }
                        catch {
                            $null = $opSignal.LogCritical("Plan.Config.Threading.DebugWorkItemIndex must be an integer.")
                            return $opSignal
                        }
                    }

                    for ($index = 0; $index -lt $warmupCount; $index++) {
                        $iterationSignal = Invoke-PlanIteration `
                            -ConductionSignal $ConductionSignal `
                            -ItemSignal $ItemSignal `
                            -Plan $Plan `
                            -Iteration $iterationArray[$index] `
                            -IterationIndex $index `
                            -IterationName $iterationName `
                            -IterationArray $iterationArray `
                        | Select-Object -Last 1

                        if ($opSignal.MergeSignalAndVerifyFailure(@($iterationSignal))) {
                            return $opSignal
                        }
                    }

                    $remainingCount = $iterationArray.Count - $warmupCount
                    if ($remainingCount -le 0) {
                        break
                    }

                    $useParallel = $warmup -ne -1 -and (
                        $debugInline -or
                        ($supportParallelism -and $maxThreads -gt 1 -and $remainingCount -gt 1)
                    )
                    if (-not $useParallel) {
                        for ($index = $warmupCount; $index -lt $iterationArray.Count; $index++) {
                            $iterationSignal = Invoke-PlanIteration `
                                -ConductionSignal $ConductionSignal `
                                -ItemSignal $ItemSignal `
                                -Plan $Plan `
                                -Iteration $iterationArray[$index] `
                                -IterationIndex $index `
                                -IterationName $iterationName `
                                -IterationArray $iterationArray `
                            | Select-Object -Last 1

                            if ($opSignal.MergeSignalAndVerifyFailure(@($iterationSignal))) {
                                return $opSignal
                            }
                        }

                        break
                    }

                    if ($null -eq $environmentDetails) {
                        $null = $opSignal.LogCritical("Parallel iteration requires Pointer.Grid.EnvironmentDetails.")
                        return $opSignal
                    }

                    $workItems = [System.Collections.Generic.List[object]]::new()
                    for ($index = $warmupCount; $index -lt $iterationArray.Count; $index++) {
                        $planCloneSignal = Resolve-ClonePlan -Plan $Plan | Select-Object -Last 1
                        if ($opSignal.MergeSignalAndVerifyFailure(@($planCloneSignal)) -or -not $planCloneSignal.HasResult()) {
                            return $opSignal
                        }

                        $workItems.Add([PSCustomObject]@{
                            Index = $index
                            Value = $iterationArray[$index]
                            Plan  = $planCloneSignal.GetResult()
                        })
                    }

                    $workerContext = [PSCustomObject]@{
                        SourceItemSignal    = $ItemSignal
                        IterationName       = $iterationName
                        IterationArray      = $iterationArray
                        ReuseItemSignalGrid = $reuseItemSignalGrid
                    }

                    $poolSignal = Invoke-STRunspacePool `
                        -Signal $opSignal `
                        -EnvironmentDefinition $environmentDetails `
                        -WorkItems @($workItems) `
                        -WorkerCommand 'Invoke-PlanIterationWorker' `
                        -ThrottleLimit $maxThreads `
                        -WorkerContext $workerContext `
                        -DebugInline:$debugInline `
                        -DebugWorkItemIndex $debugWorkItemIndex `
                    | Select-Object -Last 1

                    if ($opSignal.MergeSignalAndVerifyFailure(@($poolSignal)) -or -not $poolSignal.HasResult()) {
                        return $opSignal
                    }

                    foreach ($workerResult in @($poolSignal.GetResult() | Sort-Object -Property Index)) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$workerResult.Error)) {
                            $null = $opSignal.LogCritical("Iteration $($workerResult.Index) runspace failed: $($workerResult.Error)")
                            continue
                        }

                        if ($null -eq $workerResult.InitializationSignal) {
                            $null = $opSignal.LogCritical("Iteration $($workerResult.Index) did not return an initialization signal.")
                            continue
                        }

                        $null = $opSignal.MergeSignal(@($workerResult.InitializationSignal))
                        if ([bool]$workerResult.InitializationFailed -or $null -eq $workerResult.WorkerSignal) {
                            if ([bool]$workerResult.InitializationFailed -and -not $opSignal.Failure()) {
                                $null = $opSignal.LogCritical("Iteration $($workerResult.Index) environment initialization failed.")
                            }
                            if ($null -eq $workerResult.WorkerSignal) {
                                $null = $opSignal.LogCritical("Iteration $($workerResult.Index) did not return a worker signal.")
                            }
                            continue
                        }

                        $null = $opSignal.MergeSignal(@($workerResult.WorkerSignal))
                        if ([bool]$workerResult.WorkerFailed -and -not $opSignal.Failure()) {
                            $null = $opSignal.LogCritical("Iteration $($workerResult.Index) worker failed.")
                        }
                    }

                    if ($opSignal.Failure()) {
                        return $opSignal
                    }
                    break
                }

                "InvokePlan" {
                    #TDB
                   break
                }

                "InvokePhase" {
                     $resolveStepsSignal = $this.ResolveInsertPhaseSteps($opSignal, $ConductionSignal, $Plan, $ItemSignal)
                    if ($opSignal.MergeSignalAndVerifyFailure($resolveStepsSignal) -or (-not $resolveStepsSignal.HasResult())) {
                         return $opSignal 
                    }

                    $phase = [PSCustomObject]@{
                        Steps = @($resolveStepsSignal.GetResult())
                    }

                    $SourceSignal = Invoke-CondenserAdapter -Slot "Memory" -Activity "Generate" -Signal $ConductionSignal -Plan $phase -ItemSignal $ItemSignal | Select-Object -Last 1

                   break
                }

                "InsertPhaseSteps" {
                    $resolveStepsSignal = $this.ResolveInsertPhaseSteps($opSignal, $ConductionSignal, $Plan, $ItemSignal)
                    if ($opSignal.MergeSignalAndVerifyFailure($resolveStepsSignal) -or (-not $resolveStepsSignal.HasResult())) {
                         return $opSignal 
                    }


                    $newSteps = $resolveStepsSignal.GetResult()

                    $phaseStepsSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Phase.Steps" | Select-Object -Last 1
                    $phaseSteps = @($phaseStepsSignal.GetResult())

                    # Find the index of the current plan object inside Phase.Steps
                    $currentIndex = -1
                    for ($i = 0; $i -lt $phaseSteps.Count; $i++) {
                        if ($phaseSteps[$i].Name -eq $Plan.Name) {
                            $currentIndex = $i
                            break
                        }
                    }

                    if ($currentIndex -ge 0) {
                        $updatedSteps = @()

                        if ($currentIndex -ge 0) {
                            $updatedSteps += $phaseSteps[0..$currentIndex]
                        }

                        $updatedSteps += @($newSteps)

                        if ($currentIndex + 1 -lt $phaseSteps.Count) {
                            $updatedSteps += $phaseSteps[($currentIndex + 1)..($phaseSteps.Count - 1)]
                        }

                        $null = Add-PathToDictionary -Dictionary $Plan -Path "Phase.Steps" -Value $updatedSteps | Select-Object -Last 1
                    }
                    else {
                        $opSignal.LogCritical("Could not find the current plan step inside Phase.Steps.")
                    }

                    break
                }

                "AddPhaseSteps" {
                    $resolveStepsSignal = $this.ResolveInsertPhaseSteps($opSignal, $ConductionSignal, $Plan, $ItemSignal)
                    if ($opSignal.MergeSignalAndVerifyFailure($resolveStepsSignal) -or (-not $resolveStepsSignal.HasResult())) {
                         return $opSignal 
                    }

                    $newSteps = $resolveStepsSignal.GetResult()

                    $null = Add-PathToDictionary -Dictionary $Plan -Path "Phase.Steps" -Value $newSteps | Select-Object -Last 1

                    break
                }

                default {
                    $opSignal.LogCritical("Unsupported Activity: $Activity")
                    break
                }
            }
        }

        return $opSignal
    }
}
