function Invoke-PlanPhaseWorker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Runtime,
        [Parameter(Mandatory)][object]$WorkItem,
        [Parameter(Mandatory)][object]$Context
    )

    $opSignal = [SignalGraph.Signal]::Start("Invoke-PlanPhaseWorker:$($WorkItem.Index)", $Runtime.ConductionSignal) | Select-Object -Last 1
    try {
        $failureTaskId=Get-STFailureOptionalString $Context 'FailureTaskId'
        Set-STFailureWorkerContext $WorkItem.Phase (Get-STFailureOptionalString $Context 'FailureScopeId') $Runtime ([int]$WorkItem.Index) $failureTaskId @(Get-STFailureWorkerProofs $Context)
        $importSignal = Import-STSignalGraphSnapshot `
            -SnapshotJson ([string]$Context.SnapshotJson) `
            -ConductionSignal $Runtime.ConductionSignal `
            -Name "BackgroundPhaseItem:$($WorkItem.Index)" |
            Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($importSignal) -or -not $importSignal.HasResult()) {
            return $opSignal
        }

        $phaseSignal = Invoke-PlanPhase `
            -ConductionSignal $Runtime.ConductionSignal `
            -ItemSignal $importSignal.GetResult() `
            -Phase $WorkItem.Phase `
            -ReturnKeys @($Context.ReturnKeys) |
            Select-Object -Last 1
        $null = $opSignal.MergeSignal($phaseSignal)
        if ($phaseSignal.HasResult()) { $opSignal.SetResult($phaseSignal.GetResult()) }
    }
    catch {
        $null = $opSignal.LogCritical("Background phase worker failed: $($_.Exception.Message)", $null, $_.Exception)
    }
    finally { $frame=New-STFailureFrame $WorkItem.Phase $Runtime.ConductionSignal 'PhaseWorker' $null $null; $frame.WorkerIndex=[int]$WorkItem.Index; Add-STFailureBoundary $opSignal $frame $Runtime.ConductionSignal.Id }
    return $opSignal
}
