using module ../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

$ErrorActionPreference = 'Stop'
$foundationRoot = Join-Path $PSScriptRoot '../Src/PowerShell'
. "$foundationRoot/Utilities/Threading/STBackgroundTasks.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$signal = [Signal]::Start('BackgroundTaskTest') | Select-Object -Last 1
$fixtureModule = Join-Path $PSScriptRoot 'Fixtures/TestRunspaceWorker.psm1'

$startedAt = [DateTime]::UtcNow
$startSignal = Start-STBackgroundTask `
    -Signal $signal `
    -EnvironmentDefinition ([PSCustomObject]@{ Name = 'BackgroundEnvironment' }) `
    -WorkItem ([PSCustomObject]@{ Index = 0; Value = 'First'; DelayMilliseconds = 1500 }) `
    -WorkerContext ([PSCustomObject]@{ Name = 'BackgroundContext' }) `
    -WorkerCommand 'Test-STBackgroundWorker' `
    -TaskName 'FirstTask' `
    -OwnerId 'OwnerA' `
    -MaxConcurrent 1 `
    -FoundationModulePath $fixtureModule |
    Select-Object -Last 1

$launchDuration = ([DateTime]::UtcNow - $startedAt).TotalMilliseconds
Assert-True (-not $startSignal.Failure() -and $startSignal.HasResult()) "Background task did not start: $((@($startSignal.Entries | ForEach-Object Message)) -join ' | ')"
Assert-True ($launchDuration -lt 1000) 'Background task start waited for worker completion.'
$firstTaskId = [string]$startSignal.GetResult().TaskId

$secondSignal = Start-STBackgroundTask `
    -Signal $signal `
    -EnvironmentDefinition ([PSCustomObject]@{ Name = 'BackgroundEnvironment' }) `
    -WorkItem ([PSCustomObject]@{ Index = 1; Value = 'Second'; DelayMilliseconds = 10 }) `
    -WorkerContext ([PSCustomObject]@{ Name = 'BackgroundContext' }) `
    -WorkerCommand 'Test-STBackgroundWorker' `
    -TaskName 'SecondTask' `
    -OwnerId 'OwnerA' `
    -MaxConcurrent 1 `
    -FoundationModulePath $fixtureModule |
    Select-Object -Last 1

Assert-True ($secondSignal.GetResult().State -eq 'Queued') 'Concurrency limit did not queue the second task.'
$secondTaskId = [string]$secondSignal.GetResult().TaskId

$firstReceive = Receive-STBackgroundTask -TaskId $firstTaskId -Signal $signal -Wait | Select-Object -Last 1
Assert-True (-not $firstReceive.Failure()) 'First background task failed.'
Assert-True ($firstReceive.GetResult().CompletionEnvelope.WorkerSignal.Result.Value -eq 'First') 'First background result was not retained.'

$secondReceive = Receive-STBackgroundTask -TaskId $secondTaskId -Signal $signal -Wait | Select-Object -Last 1
Assert-True (-not $secondReceive.Failure()) 'Queued background task failed.'
Assert-True ($secondReceive.GetResult().CompletionEnvelope.WorkerSignal.Result.Value -eq 'Second') 'Queued background result was not retained.'

$allSignal = Wait-STBackgroundTasks -OwnerId 'OwnerA' -Signal $signal -RemoveAfterReceive | Select-Object -Last 1
Assert-True (-not $allSignal.Failure()) 'Owner-scoped background wait failed.'
Assert-True ((Get-STBackgroundTask -TaskId $firstTaskId -Signal $signal).Failure()) 'Removed background task remained registered.'

$failureStart = Start-STBackgroundTask `
    -Signal $signal `
    -EnvironmentDefinition ([PSCustomObject]@{ Name = 'FailureEnvironment' }) `
    -WorkItem ([PSCustomObject]@{ Index = 2 }) `
    -WorkerContext ([PSCustomObject]@{}) `
    -WorkerCommand 'Test-STPoolThrowWorker' `
    -TaskName 'FailureTask' `
    -OwnerId 'OwnerB' `
    -FoundationModulePath $fixtureModule |
    Select-Object -Last 1
$failureReceive = Receive-STBackgroundTask -TaskId $failureStart.GetResult().TaskId -Signal $signal -Wait -RemoveAfterReceive | Select-Object -Last 1
Assert-True ($failureReceive.Failure()) 'Worker exception did not fail the background task.'

$cancelStart = Start-STBackgroundTask `
    -Signal $signal `
    -EnvironmentDefinition ([PSCustomObject]@{ Name = 'CancelEnvironment' }) `
    -WorkItem ([PSCustomObject]@{ Index = 3; Value = 'Cancel'; DelayMilliseconds = 5000 }) `
    -WorkerContext ([PSCustomObject]@{ Name = 'BackgroundContext' }) `
    -WorkerCommand 'Test-STBackgroundWorker' `
    -TaskName 'CancelTask' `
    -OwnerId 'OwnerB' `
    -FoundationModulePath $fixtureModule |
    Select-Object -Last 1
$cancelSignal = Stop-STBackgroundTask -TaskId $cancelStart.GetResult().TaskId -Signal $signal | Select-Object -Last 1
Assert-True (-not $cancelSignal.Failure() -and $cancelSignal.GetResult().State -eq 'Cancelled') 'Background cancellation failed.'
$null = Receive-STBackgroundTask -TaskId $cancelStart.GetResult().TaskId -Signal $signal -RemoveAfterReceive | Select-Object -Last 1

Write-Output 'PASS: asynchronous return, completion, throttling, failures, cancellation, result retention, owner wait, and cleanup.'
