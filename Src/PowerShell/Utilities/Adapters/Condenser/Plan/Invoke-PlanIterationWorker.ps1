function Invoke-PlanIterationWorker {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Runtime,

        [Parameter(Mandatory)]
        [object]$WorkItem,

        [Parameter(Mandatory)]
        [object]$Context
    )

    $opSignal = [Signal]::Start("Invoke-PlanIterationWorker:$($WorkItem.Index)", $Runtime.ConductionSignal) | Select-Object -Last 1

    try {
        $targetGraph = $Runtime.ConductionSignal.GetPointer()
        if ($targetGraph -isnot [Graph]) {
            $null = $opSignal.LogCritical("Worker runtime does not have a Graph pointer.")
            return $opSignal
        }

        if ([bool]$Context.ReuseItemSignalGrid) {
            $forkSignal = New-SignalPointerFork `
                -SourceSignal $Context.SourceItemSignal `
                -Name "IterationItem:$($WorkItem.Index)" `
                -ReversePointer $Runtime.ConductionSignal `
                -TargetGraph $targetGraph `
                -CollisionAction PreserveTarget `
                -CopyJacket `
                -CopyResult `
            | Select-Object -Last 1

            if ($opSignal.MergeSignalAndVerifyFailure(@($forkSignal)) -or -not $forkSignal.HasResult()) {
                return $opSignal
            }

            $workerItemSignal = $forkSignal.GetResult()
        }
        else {
            $workerItemSignal = [Signal]::Start("IterationItem:$($WorkItem.Index)", $Runtime.ConductionSignal) | Select-Object -Last 1
            $null = $workerItemSignal.SetPointer($targetGraph)

            if ($null -ne $Context.SourceItemSignal.Jacket) {
                $null = $workerItemSignal.SetJacket($Context.SourceItemSignal.Jacket)
            }
            if ($null -ne $Context.SourceItemSignal.Result) {
                $workerItemSignal.SetResult($Context.SourceItemSignal.Result)
            }
        }

        $iterationSignal = Invoke-PlanIteration `
            -ConductionSignal $Runtime.ConductionSignal `
            -ItemSignal $workerItemSignal `
            -Plan $WorkItem.Plan `
            -Iteration $WorkItem.Value `
            -IterationIndex $WorkItem.Index `
            -IterationName $Context.IterationName `
            -IterationArray $Context.IterationArray `
        | Select-Object -Last 1

        $null = $opSignal.MergeSignalAndVerifyFailure(@($iterationSignal))
        $opSignal.SetResult([PSCustomObject]@{
            Index      = [int]$WorkItem.Index
            ItemSignal = $workerItemSignal
            Signal     = $iterationSignal
        })
    }
    catch {
        $null = $opSignal.LogCritical("Iteration worker $($WorkItem.Index) failed: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}
