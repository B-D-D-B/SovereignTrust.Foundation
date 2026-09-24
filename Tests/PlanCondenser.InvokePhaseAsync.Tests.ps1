using module ../../SignalGraph/Src/PowerShell/SignalGraph.psd1

$ErrorActionPreference = 'Stop'
class Conductor {}
class MappedCondenserAdapter {}

$foundationRoot = Join-Path $PSScriptRoot '../Src/PowerShell'
. "$foundationRoot/Utilities/Adapters/Condenser/Plan/Resolve-ClonePlan.ps1"
. "$foundationRoot/Utilities/Graph/Export-STSignalGraphSnapshot.ps1"
. "$foundationRoot/Classes/Adapters/Condenser/PlanCondenser.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$script:startCalls = [System.Collections.Generic.List[object]]::new()
$script:phaseCalls = 0
$script:completeCalls = [System.Collections.Generic.List[string]]::new()

function Invoke-CondenserAdapter {
    param($Slot, $Activity, $Signal, $Plan, $ItemSignal)
    $result = [Signal]::Start("StubCondenser:$Slot") | Select-Object -Last 1
    if ($Slot -eq 'Hydration') {
        $result.SetResult($ItemSignal.GetJacketResult())
    }
    return $result
}

function Invoke-PlanPhase {
    param($ConductionSignal, $ItemSignal, $Phase, $ReturnKeys)
    $script:phaseCalls++
    $result = [Signal]::Start('StubPhase') | Select-Object -Last 1
    $result.SetResult([PSCustomObject]@{ Completed = $true; ExportedResults = @() })
    return $result
}

function Start-STBackgroundTask {
    param($Signal, $EnvironmentDefinition, $WorkItem, $WorkerContext, $WorkerCommand, $TaskName, $OwnerId, $MaxConcurrent, [switch]$DebugInline)
    $script:startCalls.Add([PSCustomObject]@{
        EnvironmentDefinition = $EnvironmentDefinition
        WorkItem = $WorkItem
        WorkerContext = $WorkerContext
        WorkerCommand = $WorkerCommand
        TaskName = $TaskName
        OwnerId = $OwnerId
        MaxConcurrent = $MaxConcurrent
        DebugInline = $DebugInline.IsPresent
    })
    $result = [Signal]::Start('StubStart') | Select-Object -Last 1
    $result.SetResult([PSCustomObject]@{ TaskId = 'task-1'; TaskName = $TaskName; State = 'Running' })
    return $result
}

function Complete-PlanPhaseTask {
    param($TaskId, $ItemSignal, $Signal, $CollisionAction, [switch]$RemoveAfterReceive)
    $script:completeCalls.Add($TaskId)
    $result = [Signal]::Start('StubComplete') | Select-Object -Last 1
    $result.SetResult([PSCustomObject]@{ TaskId = $TaskId; State = 'Completed' })
    return $result
}

function Wait-STBackgroundTasks {
    param($OwnerId, $Signal, [switch]$RemoveAfterReceive)
    $result = [Signal]::Start('StubWait') | Select-Object -Last 1
    $result.SetResult(@())
    return $result
}

function Get-STBackgroundTask {
    param($TaskId, $Signal)
    $result = [Signal]::Start('StubStatus') | Select-Object -Last 1
    $result.SetResult([PSCustomObject]@{ TaskId = $TaskId; State = 'Running' })
    return $result
}

function Stop-STBackgroundTask {
    param($TaskId, $Signal)
    $result = [Signal]::Start('StubStop') | Select-Object -Last 1
    $result.SetResult([PSCustomObject]@{ TaskId = $TaskId; State = 'Cancelled' })
    return $result
}

$graph = ([Graph]::Start('AsyncPlanGraph', $null, $false) | Select-Object -Last 1).GetResult()
$environment = [PSCustomObject]@{ Config = [PSCustomObject]@{ SupportParallelism = $true } }
$null = $graph.RegisterResultAsSignal('EnvironmentDetails', $environment)
$conductionSignal = [Signal]::Start('Conduction') | Select-Object -Last 1
$null = $conductionSignal.SetPointer($graph)
$itemSignal = [Signal]::Start('Item') | Select-Object -Last 1
$null = $itemSignal.SetPointer($graph)
$itemSignal.SetResult(@([PSCustomObject]@{ Name = 'InnerStep'; Config = [PSCustomObject]@{} }))

$plan = [PSCustomObject]@{
    Name = 'AsyncPhase'
    Path = '@'
    Config = [PSCustomObject]@{
        TaskName = 'BackgroundPhase'
        ReturnKeys = @('Output')
        MaxBackgroundPhases = 2
        DebugInline = $false
        SkipRename = $true
    }
}

$condenser = New-Object PlanCondenser
$asyncSignal = $condenser.Invoke($null, 'InvokePhaseAsync', $conductionSignal, $plan, $itemSignal)
Assert-True (-not $asyncSignal.Failure() -and $asyncSignal.GetResult().TaskId -eq 'task-1') "InvokePhaseAsync did not return its task handle (Failure=$($asyncSignal.Failure()), HasResult=$($asyncSignal.HasResult()), Result=$($asyncSignal.GetResult() | ConvertTo-Json -Depth 5 -Compress)): $((@($asyncSignal.Entries | ForEach-Object Message)) -join ' | ')"
Assert-True ($script:startCalls.Count -eq 1) 'InvokePhaseAsync did not submit exactly one task.'
Assert-True ($script:startCalls[0].WorkerCommand -eq 'Invoke-PlanPhaseWorker') 'InvokePhaseAsync selected the wrong worker.'
Assert-True ($script:startCalls[0].WorkerContext.ReturnKeys[0] -eq 'Output') 'ReturnKeys were not forwarded.'
Assert-True ($script:startCalls[0].WorkerContext.SnapshotJson -like '{*') 'Graph snapshot was not forwarded.'
Assert-True ($script:phaseCalls -eq 0) 'InvokePhaseAsync executed the phase inline.'

$environment.Config.SupportParallelism = $false
$disabledSignal = $condenser.Invoke($null, 'InvokePhaseAsync', $conductionSignal, $plan, $itemSignal)
Assert-True ($disabledSignal.Failure() -and $script:startCalls.Count -eq 1) 'Environment parallelism policy did not block async dispatch.'
$environment.Config.SupportParallelism = $true

$syncSignal = $condenser.Invoke($null, 'InvokePhase', $conductionSignal, $plan, $itemSignal)
Assert-True (-not $syncSignal.Failure() -and $script:phaseCalls -eq 1) 'Synchronous InvokePhase did not use the shared phase executor.'

$awaitPlan = [PSCustomObject]@{ Path = 'task-1'; Config = [PSCustomObject]@{ ResultCollisionAction = 'Error' } }
$awaitSignal = $condenser.Invoke($null, 'AwaitPhase', $conductionSignal, $awaitPlan, $itemSignal)
Assert-True (-not $awaitSignal.Failure() -and $script:completeCalls[0] -eq 'task-1') 'AwaitPhase did not receive the requested task.'

Write-Output 'PASS: async dispatch, immediate task handles, shared synchronous execution, snapshots, return keys, and await wiring.'
