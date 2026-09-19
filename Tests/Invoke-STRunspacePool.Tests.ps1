using module ../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

$ErrorActionPreference = 'Stop'
$foundationRoot = Join-Path $PSScriptRoot '../Src/PowerShell'
. "$foundationRoot/Utilities/Threading/Invoke-STRunspacePool.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$workItems = 0..3 | ForEach-Object {
    [PSCustomObject]@{ Index = $_; Value = "Item$_" }
}

$signal = [Signal]::Start('PoolTest') | Select-Object -Last 1
$sourceGraph = ([Graph]::Start('SourceGraph', $signal, $false) | Select-Object -Last 1).GetResult()
$stateSignal = [Signal]::Start('State') | Select-Object -Last 1
$stateSignal.SetResult('SharedState')
$null = $sourceGraph.RegisterSignal('State', $stateSignal)
$sourceSignal = [Signal]::Start('SourceItem') | Select-Object -Last 1
$null = $sourceSignal.SetPointer($sourceGraph)
$workerModule = Join-Path $PSScriptRoot 'Fixtures/TestRunspaceWorker.psm1'
$poolSignal = Invoke-STRunspacePool `
    -Signal $signal `
    -EnvironmentDefinition ([PSCustomObject]@{ Name = 'TestEnvironment' }) `
    -WorkItems $workItems `
    -WorkerCommand 'Test-STPoolWorker' `
    -ThrottleLimit 2 `
    -FoundationModulePath $workerModule `
    -WorkerContext ([PSCustomObject]@{ Name = 'SharedContext'; SourceSignal = $sourceSignal }) `
| Select-Object -Last 1

Assert-True (-not $poolSignal.Failure() -and $poolSignal.HasResult()) 'Runspace pool failed.'
$results = @($poolSignal.GetResult())
Assert-True ($results.Count -eq 4) 'Runspace pool did not return every work item.'
Assert-True ((($results | ForEach-Object Index) -join ',') -eq '0,1,2,3') 'Runspace results were not index ordered.'
foreach ($result in $results) {
    Assert-True ([string]::IsNullOrWhiteSpace([string]$result.Error)) "Runspace $($result.Index) returned an error: $($result.Error)"
    Assert-True ($null -ne $result.InitializationSignal) "Runspace $($result.Index) did not initialize a runtime."
    Assert-True ($null -ne $result.WorkerSignal) "Runspace $($result.Index) did not return a worker signal."
    Assert-True (-not [bool]$result.InitializationFailed) "Runspace $($result.Index) returned initialization without a runtime."
    Assert-True (-not [bool]$result.WorkerFailed) "Runspace $($result.Index) returned a failed worker."
}
Assert-True ((@($results.WorkerSignal | ForEach-Object { $_.Result.RuntimeId } | Select-Object -Unique).Count) -eq 4) 'Work items reused initialized runtimes.'
Assert-True ((@($results.WorkerSignal | ForEach-Object { $_.Result.RunspaceId } | Select-Object -Unique).Count) -le 2) 'Runspace pool exceeded its throttle.'
Assert-True (($results.WorkerSignal | ForEach-Object { $_.Result.ContextName } | Select-Object -Unique) -eq 'SharedContext') 'Worker context was not delivered.'
Assert-True (-not ($results.WorkerSignal | Where-Object { -not $_.Result.MemberWasReused })) 'Grid members were not shallow-reused in a worker.'
Assert-True (-not ($results.WorkerSignal | Where-Object { -not $_.Result.SourceWasUnaffected })) 'A worker Grid replacement changed the source Grid.'
Assert-True ([object]::ReferenceEquals($stateSignal, $sourceGraph.Grid['State'])) 'Parallel workers changed the parent Grid registration.'

$mergedSignal = [Signal]::Start('MergedWorkers') | Select-Object -Last 1
foreach ($result in $results) {
    $null = $mergedSignal.MergeSignal(@($result.WorkerSignal))
}
Assert-True ($mergedSignal.Entries.Count -eq 4) 'Worker signal entries could not be merged in the coordinator runspace.'

$errorStreamSignal = Invoke-STRunspacePool `
    -Signal $signal `
    -EnvironmentDefinition ([PSCustomObject]@{ Name = 'ErrorStreamEnvironment' }) `
    -WorkItems @([PSCustomObject]@{ Index = 10; Value = 'ErrorItem' }) `
    -WorkerCommand 'Test-STPoolErrorWorker' `
    -ThrottleLimit 1 `
    -FoundationModulePath $workerModule `
    -WorkerContext ([PSCustomObject]@{}) `
| Select-Object -Last 1

$errorStreamResult = @($errorStreamSignal.GetResult())[0]
Assert-True ($null -ne $errorStreamResult.InitializationSignal) 'Error-stream result lost its initialization diagnostics.'
Assert-True ($null -ne $errorStreamResult.WorkerSignal) 'Error-stream result lost its worker diagnostics.'
Assert-True ($errorStreamResult.Error -like '*Requested test error*') 'Worker error-stream output was not returned.'

$throwSignal = Invoke-STRunspacePool `
    -Signal $signal `
    -EnvironmentDefinition ([PSCustomObject]@{ Name = 'ThrowEnvironment' }) `
    -WorkItems @([PSCustomObject]@{ Index = 11; Value = 'ThrowItem' }) `
    -WorkerCommand 'Test-STPoolThrowWorker' `
    -ThrottleLimit 1 `
    -FoundationModulePath $workerModule `
    -WorkerContext ([PSCustomObject]@{}) `
| Select-Object -Last 1

$throwResult = @($throwSignal.GetResult())[0]
Assert-True ($null -ne $throwResult.InitializationSignal) 'Worker exception lost its initialization diagnostics.'
Assert-True ($null -eq $throwResult.WorkerSignal) 'Worker exception unexpectedly returned a worker signal.'
Assert-True ([bool]$throwResult.WorkerFailed) 'Worker exception was not marked failed.'
Assert-True ($throwResult.Error -like '*Requested test worker exception*') 'Worker exception message was not returned.'

$invalidWorkerSignal = Invoke-STRunspacePool `
    -Signal $signal `
    -EnvironmentDefinition ([PSCustomObject]@{ Name = 'InvalidWorkerEnvironment' }) `
    -WorkItems @([PSCustomObject]@{ Index = 13; Value = 'InvalidWorkerItem' }) `
    -WorkerCommand 'Test-STPoolInvalidWorker' `
    -ThrottleLimit 1 `
    -FoundationModulePath $workerModule `
    -WorkerContext ([PSCustomObject]@{}) `
| Select-Object -Last 1

$invalidWorkerResult = @($invalidWorkerSignal.GetResult())[0]
Assert-True ($null -ne $invalidWorkerResult.InitializationSignal) 'Invalid worker response lost initialization diagnostics.'
Assert-True ($null -eq $invalidWorkerResult.WorkerSignal) 'Invalid worker response was accepted as a Signal.'
Assert-True ([bool]$invalidWorkerResult.WorkerFailed) 'Invalid worker response was not marked failed.'
Assert-True ($invalidWorkerResult.Error -like "*did not return a Signal*") 'Invalid worker response did not return a clear error.'

$initializationFailureSignal = Invoke-STRunspacePool `
    -Signal $signal `
    -EnvironmentDefinition ([PSCustomObject]@{ Name = 'InitializationFailure'; FailInitialization = $true }) `
    -WorkItems @([PSCustomObject]@{ Index = 12; Value = 'InitializationItem' }) `
    -WorkerCommand 'Test-STPoolWorker' `
    -ThrottleLimit 1 `
    -FoundationModulePath $workerModule `
    -WorkerContext ([PSCustomObject]@{ Name = 'Unused'; SourceSignal = $sourceSignal }) `
| Select-Object -Last 1

$initializationFailureResult = @($initializationFailureSignal.GetResult())[0]
Assert-True ($null -ne $initializationFailureResult.InitializationSignal) 'Initialization failure lost its diagnostic signal.'
Assert-True ([bool]$initializationFailureResult.InitializationFailed) 'Initialization failure was not marked failed.'
Assert-True ($initializationFailureResult.InitializationSignal.Failure()) 'Initialization critical entry was not reconstructed.'
Assert-True ($null -eq $initializationFailureResult.WorkerSignal) 'Worker ran after initialization failed.'

$duplicateIndexSignal = Invoke-STRunspacePool `
    -Signal $signal `
    -EnvironmentDefinition ([PSCustomObject]@{ Name = 'DuplicateIndexEnvironment' }) `
    -WorkItems @(
        [PSCustomObject]@{ Index = 20; Value = 'First' },
        [PSCustomObject]@{ Index = 20; Value = 'Second' }
    ) `
    -WorkerCommand 'Test-STPoolWorker' `
    -ThrottleLimit 1 `
    -FoundationModulePath $workerModule `
    -WorkerContext ([PSCustomObject]@{ Name = 'Duplicate'; SourceSignal = $sourceSignal }) `
| Select-Object -Last 1

Assert-True ($duplicateIndexSignal.Failure()) 'Duplicate work-item indexes were accepted.'

Import-Module $workerModule -Force
$inlineSignal = Invoke-STRunspacePool `
    -Signal $signal `
    -EnvironmentDefinition ([PSCustomObject]@{ Name = 'InlineTestEnvironment' }) `
    -WorkItems $workItems `
    -WorkerCommand 'Test-STPoolWorker' `
    -ThrottleLimit 2 `
    -FoundationModulePath $workerModule `
    -WorkerContext ([PSCustomObject]@{ Name = 'InlineContext'; SourceSignal = $sourceSignal }) `
    -DebugInline `
    -DebugWorkItemIndex 2 `
| Select-Object -Last 1

Assert-True (-not $inlineSignal.Failure() -and $inlineSignal.HasResult()) 'Inline worker execution failed.'
$inlineResults = @($inlineSignal.GetResult())
Assert-True ($inlineResults.Count -eq 4) 'Inline debugging did not execute all work items.'
Assert-True (($inlineResults.Index -join ',') -eq '0,1,2,3') 'Inline debugging skipped or reordered work items.'
Assert-True ($inlineResults[0].WorkerSignal.Result.ContextName -eq 'InlineContext') 'Inline worker context was not delivered.'
Assert-True ($inlineResults[0].WorkerSignal.Result.RunspaceId -eq [runspace]::DefaultRunspace.InstanceId.ToString()) 'Inline debugging did not execute in the caller runspace.'

Assert-True ($throwSignal.Failure()) 'Worker exception did not fail the parent pool signal.'
Assert-True ($throwResult.Error.Contains('ScriptStackTrace:')) 'Worker exception lost its script stack.'
Assert-True ($errorStreamSignal.Failure()) 'Error stream did not fail the parent pool signal.'
Assert-True ($initializationFailureSignal.Failure()) 'Initialization failure did not fail the parent pool signal.'
Assert-True ((@($inlineResults.WorkerSignal.Result.RuntimeId | Select-Object -Unique)).Count -eq 4) 'Inline items did not initialize fresh runtimes.'
Write-Output 'PASS: ordered collection, fresh runtimes, diagnostics, failures, validation, throttling, and inline debugging.'
