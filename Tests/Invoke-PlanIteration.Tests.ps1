using module ../../SignalGraph/Src/PowerShell/SignalGraph.psd1

$ErrorActionPreference = 'Stop'
$foundationRoot = Join-Path $PSScriptRoot '../Src/PowerShell'
. "$foundationRoot/Utilities/Adapters/Condenser/Plan/Resolve-ClonePlan.ps1"
. "$foundationRoot/Utilities/Adapters/Condenser/Plan/Invoke-PlanIteration.ps1"
. "$foundationRoot/Utilities/Adapters/Condenser/Plan/Invoke-PlanIterationWorker.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$script:invocation = $null
function Invoke-CondenserAdapter {
    param($Slot, $Activity, $Plan, $Signal, $ItemSignal)

    $script:invocation = [PSCustomObject]@{
        Slot       = $Slot
        Activity   = $Activity
        Plan       = $Plan
        ItemSignal = $ItemSignal
    }
    return [Signal]::Start('StubIterationResult') | Select-Object -Last 1
}

$itemGraph = ([Graph]::Start('ItemGraph', $null, $false) | Select-Object -Last 1).GetResult()
$itemSignal = [Signal]::Start('Item') | Select-Object -Last 1
$null = $itemSignal.SetPointer($itemGraph)
$conductionSignal = [Signal]::Start('Conduction') | Select-Object -Last 1
$plan = [PSCustomObject]@{
    Adapter  = 'Condenser.Plan'
    Activity = 'IteratePhase'
    Config   = [PSCustomObject]@{ Activity = 'InvokePhase' }
}
$iterations = @('A', 'B')

$result = Invoke-PlanIteration `
    -ConductionSignal $conductionSignal `
    -ItemSignal $itemSignal `
    -Plan $plan `
    -Iteration $iterations[1] `
    -IterationIndex 1 `
    -IterationName 'CurrentItem' `
    -IterationArray $iterations `
| Select-Object -Last 1

Assert-True (-not $result.Failure() -and $result.HasResult()) 'Single iteration execution failed.'
Assert-True ($itemGraph.Grid.Contains('CurrentItem')) 'Iteration signal was not registered.'
Assert-True ($itemGraph.Grid['CurrentItem'].GetResult() -eq 'B') 'Iteration value was not registered.'
Assert-True ($itemGraph.Grid['CurrentItem'].GetProperty('IterationIndex') -eq 1) 'Iteration index metadata was not registered.'
Assert-True ($script:invocation.Slot -eq 'Plan' -and $script:invocation.Activity -eq 'InvokePhase') 'Iteration invoked the wrong adapter activity.'
Assert-True ($script:invocation.Plan.Activity -eq 'InvokePhase') 'Iteration clone activity was not updated.'
Assert-True ($plan.Activity -eq 'IteratePhase') 'Iteration execution mutated the caller plan.'

$runtimeConductionSignal = [Signal]::Start('WorkerConduction') | Select-Object -Last 1
$runtimeGraph = ([Graph]::Start('WorkerGraph', $runtimeConductionSignal, $false) | Select-Object -Last 1).GetResult()
$null = $runtimeConductionSignal.SetPointer($runtimeGraph)
$workerSignal = Invoke-PlanIterationWorker `
    -Runtime ([PSCustomObject]@{ ConductionSignal = $runtimeConductionSignal }) `
    -WorkItem ([PSCustomObject]@{ Index = 1; Value = 'B'; Plan = $plan }) `
    -Context ([PSCustomObject]@{
        SourceItemSignal    = $itemSignal
        IterationName       = 'CurrentItem'
        IterationArray      = $iterations
        ReuseItemSignalGrid = $false
    }) `
| Select-Object -Last 1

Assert-True (-not $workerSignal.Failure() -and $workerSignal.HasResult()) 'Plan iteration worker failed.'
$workerResult = $workerSignal.GetResult()
Assert-True ($workerResult.Index -eq 1 -and $workerResult.Completed) 'Plan iteration worker returned the wrong status.'
Assert-True ($workerResult.PSObject.Properties.Name -notcontains 'ItemSignal') 'Plan iteration worker retained its runtime ItemSignal.'
Assert-True ($workerResult.PSObject.Properties.Name -notcontains 'Signal') 'Plan iteration worker retained its nested execution Signal.'

Write-Output 'PASS: plan cloning, iteration dispatch, metadata, and compact worker results.'
