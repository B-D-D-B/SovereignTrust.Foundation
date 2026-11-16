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

    $opSignal = [SignalGraph.Signal]::Start("Invoke-PlanIterationWorker:$($WorkItem.Index)", $Runtime.ConductionSignal) | Select-Object -Last 1
    Write-Verbose "Invoke-PlanIterationWorker: $($WorkItem.Index) - $($WorkItem.Value)"
    try {
        Set-STFailureWorkerContext $WorkItem.Plan (Get-STFailureOptionalString $Context 'FailureScopeId') $Runtime ([int]$WorkItem.Index) $null @(Get-STFailureWorkerProofs $Context)
        $targetGraph = $Runtime.ConductionSignal.GetPointer()
        if ($targetGraph -isnot [SignalGraph.Graph]) {
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
            $workerItemSignal = [SignalGraph.Signal]::Start("IterationItem:$($WorkItem.Index)", $Runtime.ConductionSignal) | Select-Object -Last 1
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

        $iterationFailed = $opSignal.MergeSignalAndVerifyFailure(@($iterationSignal))
        $opSignal.SetResult([PSCustomObject]@{
            Index     = [int]$WorkItem.Index
            Completed = -not $iterationFailed
        })
    }
    catch {
        $null = $opSignal.LogCritical("Iteration worker $($WorkItem.Index) failed: $($_.Exception.Message)", $null, $_.Exception)
    }
    finally { $frame=New-STFailureFrame $WorkItem.Plan $Runtime.ConductionSignal 'IterationWorker' $null $null; $frame.WorkerIndex=[int]$WorkItem.Index; Add-STFailureBoundary $opSignal $frame $Runtime.ConductionSignal.Id }

    return $opSignal
}
