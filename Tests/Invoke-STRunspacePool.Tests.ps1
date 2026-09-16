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
Assert-True ($inlineResults.Count -eq 1) 'Inline debugging executed more than the selected work item.'
Assert-True ($inlineResults[0].Index -eq 2) 'Inline debugging executed the wrong work item.'
Assert-True ($inlineResults[0].WorkerSignal.Result.ContextName -eq 'InlineContext') 'Inline worker context was not delivered.'
Assert-True ($inlineResults[0].WorkerSignal.Result.RunspaceId -eq [runspace]::DefaultRunspace.InstanceId.ToString()) 'Inline debugging did not execute in the caller runspace.'

Write-Output 'PASS: ordered collection, fresh per-item runtimes, worker context, runspace throttling, and inline debugging.'
