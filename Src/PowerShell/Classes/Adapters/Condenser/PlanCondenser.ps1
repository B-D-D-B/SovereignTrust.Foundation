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
                    $threadingEnabledSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Threading.Enabled" -Default $false | Select-Object -Last 1

                    if ($opSignal.MergeSignalAndVerifyFailure(@($iterationArraySignal, $iterationNameSignal, $threadingEnabledSignal))) {
                        return $opSignal
                    }

                    $iterationArray = @($iterationArraySignal.GetResult())
                    $iterationName = [string]$iterationNameSignal.GetResult()
                    if ($iterationArray.Count -eq 0) {
                        break
                    }

                    if ($threadingEnabledSignal.GetResult() -isnot [bool]) {
                        $null = $opSignal.LogCritical("Plan.Config.Threading.Enabled must be a boolean.")
                        return $opSignal
                    }
                    $threadingEnabled = $threadingEnabledSignal.GetResult()
                    $useParallel = $false
                    $warmupCount = $iterationArray.Count
                    $environmentDetails = $null
                    $maxThreads = $null
                    $reuseItemSignalGrid = $null
                    $debugInline = $null
                    $debugWorkItemIndex = $null
                    if ($threadingEnabled) {
                        $warmupSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Threading.Warmup" -Default 0 | Select-Object -Last 1
                        if ($opSignal.MergeSignalAndVerifyFailure($warmupSignal)) { return $opSignal }
                        try {
                            $warmup = [int]$warmupSignal.GetResult()
                        }
                        catch {
                            $null = $opSignal.LogCritical("Plan.Config.Threading.Warmup must be an integer.")
                            return $opSignal
                        }
                        if ($warmup -lt 0) {
                            $null = $opSignal.LogCritical("Plan.Config.Threading.Warmup cannot be less than 0.")
                            return $opSignal
                        }

                        $environmentDetailsSignal = Resolve-PathFromDictionary -Dictionary $ConductionSignal -Path "*.#.EnvironmentDetails.@" -Default $null | Select-Object -Last 1
                        $supportParallelismSignal = Resolve-PathFromDictionary -Dictionary $ConductionSignal -Path "*.#.EnvironmentDetails.@.Config.SupportParallelism" -Default $false | Select-Object -Last 1
                        $maxParallelismSignal = Resolve-PathFromDictionary -Dictionary $ConductionSignal -Path "*.#.EnvironmentDetails.@.Config.MaxParallelism" -Default 1 | Select-Object -Last 1
                        $reuseItemSignalGridSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Threading.ReuseItemSignalGrid" -Default $false | Select-Object -Last 1
                        $debugInlineSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Threading.DebugInline" -Default $false | Select-Object -Last 1
                        if ($opSignal.MergeSignalAndVerifyFailure(@($environmentDetailsSignal, $supportParallelismSignal, $maxParallelismSignal, $reuseItemSignalGridSignal, $debugInlineSignal))) {
                            return $opSignal
                        }

                        $environmentDetails = $environmentDetailsSignal.GetResult()
                        foreach ($booleanSettingSignal in @($supportParallelismSignal, $reuseItemSignalGridSignal, $debugInlineSignal)) {
                            if ($booleanSettingSignal.GetResult() -isnot [bool]) {
                                $null = $opSignal.LogCritical("SupportParallelism, ReuseItemSignalGrid, and DebugInline must be booleans.")
                                return $opSignal
                            }
                        }
                        $supportParallelism = [bool]$supportParallelismSignal.GetResult()
                        $maxThreadsSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Threading.MaxThreads" -Default $maxParallelismSignal.GetResult() | Select-Object -Last 1
                        if ($opSignal.MergeSignalAndVerifyFailure($maxThreadsSignal)) { return $opSignal }
                        try {
                            $null = [int]$maxParallelismSignal.GetResult()
                            $maxThreads = [Math]::Max(1, [int]$maxThreadsSignal.GetResult())
                        }
                        catch {
                            $null = $opSignal.LogCritical("Threading MaxThreads and environment MaxParallelism must be integers.")
                            return $opSignal
                        }

                        $reuseItemSignalGrid = [bool]$reuseItemSignalGridSignal.GetResult()
                        $debugInline = [bool]$debugInlineSignal.GetResult()

                        $warmupCount = [Math]::Min($warmup, $iterationArray.Count)

                        $debugWorkItemIndexSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Threading.DebugWorkItemIndex" -Default $warmupCount | Select-Object -Last 1
                        if ($opSignal.MergeSignalAndVerifyFailure($debugWorkItemIndexSignal)) { return $opSignal }
                        try {
                            $debugWorkItemIndex = [int]$debugWorkItemIndexSignal.GetResult()
                        }
                        catch {
                            $null = $opSignal.LogCritical("Plan.Config.Threading.DebugWorkItemIndex must be an integer.")
                            return $opSignal
                        }

                        $remainingCount = $iterationArray.Count - $warmupCount
                        $useParallel = $remainingCount -gt 0 -and (
                            $debugInline -or
                            ($supportParallelism -and $maxThreads -gt 1 -and $remainingCount -gt 1)
                        )
                    }

                    # Serial-only execution and serial fallback share the same loop.
                    $serialCount = if ($useParallel) { $warmupCount } else { $iterationArray.Count }
                    for ($index = 0; $index -lt $serialCount; $index++) {
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

                    if (-not $useParallel) {
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

                    $null = $opSignal.MergeSignal(@($poolSignal))
                    if (-not $poolSignal.HasResult()) {
                        return $opSignal
                    }

                    foreach ($workerResult in @($poolSignal.GetResult() | Sort-Object -Property Index)) {
                        if ($null -eq $workerResult.InitializationSignal) {
                            $null = $opSignal.LogCritical("Iteration $($workerResult.Index) did not return an initialization signal.")
                        }
                        else {
                            if ([bool]$workerResult.InitializationFailed -and -not $workerResult.InitializationSignal.Failure()) {
                                $null = $opSignal.LogCritical("Iteration $($workerResult.Index) environment initialization failed.")
                            }
                            $null = $opSignal.MergeSignal(@($workerResult.InitializationSignal))
                        }

                        if ($null -eq $workerResult.WorkerSignal) {
                            $null = $opSignal.LogCritical("Iteration $($workerResult.Index) did not return a worker signal.")
                        }
                        else {
                            if ([bool]$workerResult.WorkerFailed -and -not $workerResult.WorkerSignal.Failure()) {
                                $null = $opSignal.LogCritical("Iteration $($workerResult.Index) worker failed.")
                            }
                            $null = $opSignal.MergeSignal(@($workerResult.WorkerSignal))
                        }

                        if (-not [string]::IsNullOrWhiteSpace([string]$workerResult.Error)) {
                            $null = $opSignal.LogCritical("Iteration $($workerResult.Index) runspace failed: $($workerResult.Error)")
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

                    $phaseSignal = Invoke-PlanPhase `
                        -ConductionSignal $ConductionSignal `
                        -ItemSignal $ItemSignal `
                        -Phase $phase |
                        Select-Object -Last 1
                    $null = $opSignal.MergeSignal($phaseSignal)

                    break
                }

                "InvokePhaseAsync" {
                    $resolveStepsSignal = $this.ResolveInsertPhaseSteps($opSignal, $ConductionSignal, $Plan, $ItemSignal)
                    if ($opSignal.MergeSignalAndVerifyFailure($resolveStepsSignal) -or (-not $resolveStepsSignal.HasResult())) {
                        return $opSignal
                    }

                    $environmentSignal = Resolve-PathFromDictionary -Dictionary $ConductionSignal -Path "*.#.EnvironmentDetails.@" -Default $null | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($environmentSignal) -or -not $environmentSignal.HasResult()) {
                        $null = $opSignal.LogCritical('InvokePhaseAsync requires Pointer.Grid.EnvironmentDetails.')
                        return $opSignal
                    }
                    $supportParallelismSignal = Resolve-PathFromDictionary -Dictionary $environmentSignal.GetResult() -Path 'Config.SupportParallelism' -Default $false | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($supportParallelismSignal)) { return $opSignal }
                    if ($supportParallelismSignal.GetResult() -isnot [bool]) {
                        $null = $opSignal.LogCritical('Environment Config.SupportParallelism must be a boolean.')
                        return $opSignal
                    }
                    if (-not [bool]$supportParallelismSignal.GetResult()) {
                        $null = $opSignal.LogCritical('InvokePhaseAsync requires Environment Config.SupportParallelism to be true.')
                        return $opSignal
                    }

                    $snapshotSignal = Export-STSignalGraphSnapshot -ItemSignal $ItemSignal -Signal $opSignal | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($snapshotSignal) -or -not $snapshotSignal.HasResult()) {
                        return $opSignal
                    }

                    $taskNameSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path 'Config.TaskName' -Default $Plan.Name | Select-Object -Last 1
                    $returnKeysSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path 'Config.ReturnKeys' -Default @() | Select-Object -Last 1
                    $debugInlineSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path 'Config.DebugInline' -Default $false | Select-Object -Last 1
                    $environmentMaxSignal = Resolve-PathFromDictionary -Dictionary $environmentSignal.GetResult() -Path 'Config.MaxBackgroundPhases' -Default 4 | Select-Object -Last 1
                    $maxBackgroundSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path 'Config.MaxBackgroundPhases' -Default $environmentMaxSignal.GetResult() | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure(@($taskNameSignal, $returnKeysSignal, $debugInlineSignal, $environmentMaxSignal, $maxBackgroundSignal))) {
                        return $opSignal
                    }
                    if ($debugInlineSignal.GetResult() -isnot [bool]) {
                        $null = $opSignal.LogCritical('Config.DebugInline must be a boolean.')
                        return $opSignal
                    }
                    try { $maxBackgroundPhases = [int]$maxBackgroundSignal.GetResult() }
                    catch {
                        $null = $opSignal.LogCritical('Config.MaxBackgroundPhases must be an integer.')
                        return $opSignal
                    }
                    if ($maxBackgroundPhases -lt 1) {
                        $null = $opSignal.LogCritical('Config.MaxBackgroundPhases must be greater than zero.')
                        return $opSignal
                    }

                    $phase = [PSCustomObject]@{ Steps = @($resolveStepsSignal.GetResult()) }
                    $ownerId = "Item:$([System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($ItemSignal))"
                    $workItem = [PSCustomObject]@{ Index = 0; Phase = $phase }
                    $workerContext = [PSCustomObject]@{
                        SnapshotJson = [string]$snapshotSignal.GetResult()
                        ReturnKeys   = @($returnKeysSignal.GetResult())
                    }

                    $startSignal = Start-STBackgroundTask `
                        -Signal $opSignal `
                        -EnvironmentDefinition $environmentSignal.GetResult() `
                        -WorkItem $workItem `
                        -WorkerContext $workerContext `
                        -WorkerCommand 'Invoke-PlanPhaseWorker' `
                        -TaskName ([string]$taskNameSignal.GetResult()) `
                        -OwnerId $ownerId `
                        -MaxConcurrent $maxBackgroundPhases `
                        -DebugInline:([bool]$debugInlineSignal.GetResult()) |
                        Select-Object -Last 1
                    $null = $opSignal.MergeSignal($startSignal)
                    if ($startSignal.HasResult()) { $opSignal.SetResult($startSignal.GetResult()) }

                    break
                }

                "AwaitPhase" {
                    $taskId = if ($DefaultPath -is [string]) { $DefaultPath } else { [string]$DefaultPath.TaskId }
                    if ([string]::IsNullOrWhiteSpace($taskId)) {
                        $null = $opSignal.LogCritical('AwaitPhase requires a task ID in Plan.Path.')
                        return $opSignal
                    }

                    $collisionSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path 'Config.ResultCollisionAction' -Default 'Error' | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($collisionSignal)) { return $opSignal }
                    if ([string]$collisionSignal.GetResult() -notin @('Error', 'PreserveParent', 'OverwriteParent')) {
                        $null = $opSignal.LogCritical('Config.ResultCollisionAction must be Error, PreserveParent, or OverwriteParent.')
                        return $opSignal
                    }
                    $completeSignal = Complete-PlanPhaseTask `
                        -TaskId $taskId `
                        -ItemSignal $ItemSignal `
                        -Signal $opSignal `
                        -CollisionAction ([string]$collisionSignal.GetResult()) `
                        -RemoveAfterReceive |
                        Select-Object -Last 1
                    $null = $opSignal.MergeSignal($completeSignal)
                    if ($completeSignal.HasResult()) { $opSignal.SetResult($completeSignal.GetResult()) }

                    break
                }

                "AwaitAllPhases" {
                    $ownerId = "Item:$([System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($ItemSignal))"
                    $collisionSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path 'Config.ResultCollisionAction' -Default 'Error' | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($collisionSignal)) { return $opSignal }
                    if ([string]$collisionSignal.GetResult() -notin @('Error', 'PreserveParent', 'OverwriteParent')) {
                        $null = $opSignal.LogCritical('Config.ResultCollisionAction must be Error, PreserveParent, or OverwriteParent.')
                        return $opSignal
                    }

                    $waitSignal = Wait-STBackgroundTasks -OwnerId $ownerId -Signal $opSignal | Select-Object -Last 1
                    $null = $opSignal.MergeSignal($waitSignal)
                    foreach ($received in @($waitSignal.GetResult())) {
                        $completeSignal = Complete-PlanPhaseTask `
                            -TaskId ([string]$received.Status.TaskId) `
                            -ItemSignal $ItemSignal `
                            -Signal $opSignal `
                            -CollisionAction ([string]$collisionSignal.GetResult()) `
                            -RemoveAfterReceive |
                            Select-Object -Last 1
                        $null = $opSignal.MergeSignal($completeSignal)
                    }
                    $opSignal.SetResult(@($waitSignal.GetResult() | ForEach-Object Status))

                    break
                }

                "GetPhaseStatus" {
                    $taskId = if ($DefaultPath -is [string]) { $DefaultPath } else { [string]$DefaultPath.TaskId }
                    $statusSignal = Get-STBackgroundTask -TaskId $taskId -Signal $opSignal | Select-Object -Last 1
                    $null = $opSignal.MergeSignal($statusSignal)
                    if ($statusSignal.HasResult()) { $opSignal.SetResult($statusSignal.GetResult()) }

                    break
                }

                "StopPhase" {
                    $taskId = if ($DefaultPath -is [string]) { $DefaultPath } else { [string]$DefaultPath.TaskId }
                    $stopSignal = Stop-STBackgroundTask -TaskId $taskId -Signal $opSignal | Select-Object -Last 1
                    $null = $opSignal.MergeSignal($stopSignal)
                    if ($stopSignal.HasResult()) { $opSignal.SetResult($stopSignal.GetResult()) }

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
