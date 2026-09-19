using module ../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

$ErrorActionPreference = 'Stop'

class Conductor {}
class MappedCondenserAdapter {}

$foundationRoot = Join-Path $PSScriptRoot '../Src/PowerShell'
. "$foundationRoot/Utilities/Adapters/Condenser/Plan/Resolve-ClonePlan.ps1"
. "$foundationRoot/Classes/Adapters/Condenser/PlanCondenser.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$script:sequentialIndices = [System.Collections.Generic.List[int]]::new()
$script:poolCalls = [System.Collections.Generic.List[object]]::new()
$script:returnPoolError = $false

function Invoke-PlanIteration {
    param(
        $ConductionSignal,
        $ItemSignal,
        $Plan,
        $Iteration,
        [int]$IterationIndex,
        $IterationName,
        $IterationArray
    )

    $script:sequentialIndices.Add($IterationIndex)
    return [Signal]::Start("Sequential:$IterationIndex") | Select-Object -Last 1
}

function Invoke-STRunspacePool {
    param(
        $Signal,
        $EnvironmentDefinition,
        $WorkItems,
        $WorkerCommand,
        $ThrottleLimit,
        $WorkerContext,
        [switch]$DebugInline,
        [int]$DebugWorkItemIndex
    )

    $script:poolCalls.Add([PSCustomObject]@{
        WorkItems      = @($WorkItems)
        WorkerCommand  = $WorkerCommand
        ThrottleLimit  = $ThrottleLimit
        WorkerContext  = $WorkerContext
        DebugInline     = $DebugInline.IsPresent
        DebugWorkItemIndex = $DebugWorkItemIndex
    })

    $poolSignal = [Signal]::Start('StubPool') | Select-Object -Last 1
    $poolSignal.SetResult(@($WorkItems | ForEach-Object {
        $initializationSignal = [Signal]::Start("Initialization:$($_.Index)") | Select-Object -Last 1
        $workerSignal = [Signal]::Start("Worker:$($_.Index)") | Select-Object -Last 1
        if ($script:returnPoolError) {
            $null = $initializationSignal.LogInformation("Initialization diagnostic $($_.Index)")
            $null = $workerSignal.LogInformation("Worker diagnostic $($_.Index)")
        }

        [PSCustomObject]@{
            Index                = $_.Index
            InitializationSignal = $initializationSignal
            InitializationFailed = $false
            WorkerSignal         = $workerSignal
            WorkerFailed         = $false
            Error                = if ($script:returnPoolError) { "Runspace diagnostic $($_.Index)" } else { $null }
        }
    }))
    return $poolSignal
}

function New-TestContext([bool]$SupportParallelism, [int]$MaxParallelism) {
    $environment = [PSCustomObject]@{
        Config = [PSCustomObject]@{
            SupportParallelism = $SupportParallelism
            MaxParallelism     = $MaxParallelism
        }
    }

    $graph = ([Graph]::Start('TestGraph', $null, $false) | Select-Object -Last 1).GetResult()
    $null = $graph.RegisterResultAsSignal('EnvironmentDetails', $environment)

    $conductionSignal = [Signal]::Start('Conduction') | Select-Object -Last 1
    $null = $conductionSignal.SetPointer($graph)
    $itemSignal = [Signal]::Start('Item') | Select-Object -Last 1
    $null = $itemSignal.SetPointer($graph)

    return [PSCustomObject]@{
        ConductionSignal = $conductionSignal
        ItemSignal       = $itemSignal
    }
}

function New-TestPlan([object]$Threading) {
    return [PSCustomObject]@{
        Name     = 'Iterate'
        Path     = '@'
        Adapter  = 'Condenser.Plan'
        Activity = 'IteratePhase'
        Config   = [PSCustomObject]@{
            Activity       = 'InvokePhase'
            IterationArray = @('A', 'B', 'C', 'D', 'E')
            IterationName  = 'CurrentItem'
            Threading      = $Threading
        }
    }
}

$condenser = New-Object PlanCondenser
$context = New-TestContext -SupportParallelism $true -MaxParallelism 3
$plan = New-TestPlan -Threading ([PSCustomObject]@{
    Enabled            = $true
    Warmup             = 2
    MaxThreads          = 4
    ReuseItemSignalGrid = $true
})

$result = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $plan, $context.ItemSignal)
Assert-True (-not $result.Failure()) 'Warmup/parallel split failed.'
Assert-True (($script:sequentialIndices -join ',') -eq '0,1') 'Warmup did not execute exactly the sequential prefix.'
Assert-True ($script:poolCalls.Count -eq 1) 'Parallel remainder was not submitted once.'
Assert-True ((($script:poolCalls[0].WorkItems.Index) -join ',') -eq '2,3,4') 'Parallel remainder contained the wrong indexes.'
Assert-True ($script:poolCalls[0].ThrottleLimit -eq 4) 'Plan MaxThreads was not honored.'
Assert-True ($script:poolCalls[0].WorkerCommand -eq 'Invoke-PlanIterationWorker') 'Wrong worker command was selected.'
Assert-True ($script:poolCalls[0].WorkerContext.ReuseItemSignalGrid) 'Grid reuse configuration was not forwarded.'

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$serialPlan = New-TestPlan -Threading ([PSCustomObject]@{ Enabled = $false; Warmup = -1; MaxThreads = 'invalid'; DebugWorkItemIndex = 'invalid'; DebugInline = 'invalid'; ReuseItemSignalGrid = 'invalid' })
$serialResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $serialPlan, $context.ItemSignal)
Assert-True (-not $serialResult.Failure()) 'Disabled threading validated unused settings.'
Assert-True (($script:sequentialIndices -join ',') -eq '0,1,2,3,4') 'Disabled threading did not execute every iteration sequentially.'
Assert-True ($script:poolCalls.Count -eq 0) 'Disabled threading unexpectedly started a runspace pool.'

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$disabledContext = New-TestContext -SupportParallelism $false -MaxParallelism 8
$disabledPlan = New-TestPlan -Threading ([PSCustomObject]@{ Enabled = $true; Warmup = 0; MaxThreads = 8 })
$disabledResult = $condenser.Invoke($null, 'IteratePhase', $disabledContext.ConductionSignal, $disabledPlan, $disabledContext.ItemSignal)
Assert-True (-not $disabledResult.Failure()) 'Global parallelism-disabled execution failed.'
Assert-True (($script:sequentialIndices -join ',') -eq '0,1,2,3,4') 'Global parallelism switch did not force sequential execution.'
Assert-True ($script:poolCalls.Count -eq 0) 'Global parallelism switch unexpectedly started a runspace pool.'

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$defaultPlan = New-TestPlan -Threading $null
$defaultResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $defaultPlan, $context.ItemSignal)
Assert-True (-not $defaultResult.Failure()) 'Default threading execution failed.'
Assert-True (($script:sequentialIndices -join ',') -eq '0,1,2,3,4') 'Missing Enabled did not default to sequential execution.'
Assert-True ($script:poolCalls.Count -eq 0) 'Missing Enabled unexpectedly started a runspace pool.'

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$defaultPlan = New-TestPlan -Threading ([PSCustomObject]@{ Enabled = $true })
$defaultResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $defaultPlan, $context.ItemSignal)
Assert-True (-not $defaultResult.Failure()) 'Enabled threading with default options failed.'
Assert-True ($script:sequentialIndices.Count -eq 0) 'Missing Warmup did not default to zero.'
Assert-True ((($script:poolCalls[0].WorkItems.Index) -join ',') -eq '0,1,2,3,4') 'Default threading did not submit the complete array.'
Assert-True ($script:poolCalls[0].ThrottleLimit -eq 3) 'Default threading did not use environment MaxParallelism.'
Assert-True (-not $script:poolCalls[0].WorkerContext.ReuseItemSignalGrid) 'Grid reuse did not default to false.'
Assert-True (-not $script:poolCalls[0].DebugInline) 'Inline debugging did not default to false.'
Assert-True ($script:poolCalls[0].DebugWorkItemIndex -eq 0) 'Debug index did not default to the first remaining iteration.'

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$explicitDisabledPlan = New-TestPlan -Threading ([PSCustomObject]@{ Enabled = $false; Warmup = 0; DebugInline = $true; MaxThreads = 8 })
$explicitDisabledResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $explicitDisabledPlan, $context.ItemSignal)
Assert-True (-not $explicitDisabledResult.Failure()) 'Explicit threading-disabled execution failed.'
Assert-True (($script:sequentialIndices -join ',') -eq '0,1,2,3,4') 'Enabled false did not force sequential execution.'
Assert-True ($script:poolCalls.Count -eq 0) 'Inline debugging bypassed Enabled false.'

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$inlinePlan = New-TestPlan -Threading ([PSCustomObject]@{
    Enabled           = $true
    Warmup            = 1
    MaxThreads         = 1
    DebugInline        = $true
    DebugWorkItemIndex = 3
})
$inlineResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $inlinePlan, $context.ItemSignal)
Assert-True (-not $inlineResult.Failure()) 'Inline debugging dispatch failed.'
Assert-True (($script:sequentialIndices -join ',') -eq '0') 'Inline debugging did not retain the warmup prefix.'
Assert-True ($script:poolCalls.Count -eq 1) 'Inline debugging did not dispatch through the runspace helper.'
Assert-True ($script:poolCalls[0].DebugInline) 'Inline debugging configuration was not forwarded.'
Assert-True ($script:poolCalls[0].DebugWorkItemIndex -eq 3) 'Inline debugging work-item index was not forwarded.'

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$clampedPlan = New-TestPlan -Threading ([PSCustomObject]@{ Enabled = $true; Warmup = 99; MaxThreads = 8 })
$clampedResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $clampedPlan, $context.ItemSignal)
Assert-True (-not $clampedResult.Failure()) 'Clamped warmup execution failed.'
Assert-True (($script:sequentialIndices -join ',') -eq '0,1,2,3,4') 'Warmup was not clamped to the iteration count.'
Assert-True ($script:poolCalls.Count -eq 0) 'Clamped warmup unexpectedly started a runspace pool.'

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$script:returnPoolError = $true
$diagnosticPlan = New-TestPlan -Threading ([PSCustomObject]@{ Enabled = $true; Warmup = 0; MaxThreads = 2 })
$diagnosticResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $diagnosticPlan, $context.ItemSignal)
$diagnosticMessages = @($diagnosticResult.Entries | ForEach-Object { [string]$_.Message })
Assert-True ($diagnosticResult.Failure()) 'Runspace error did not fail the plan iteration.'
Assert-True ($diagnosticMessages -contains 'Initialization diagnostic 0') 'Runspace error discarded initialization diagnostics.'
Assert-True ($diagnosticMessages -contains 'Worker diagnostic 0') 'Runspace error discarded worker diagnostics.'
Assert-True (($diagnosticMessages | Where-Object { $_ -like '*Runspace diagnostic 0*' }).Count -gt 0) 'Runspace error message was not logged.'
$script:returnPoolError = $false

foreach ($invalidThreading in @(
    @{ Enabled = 'false' },
    @{ Enabled = $true; Warmup = 'invalid' },
    @{ Enabled = $true; Warmup = -1 },
    @{ Enabled = $true; Warmup = -2 },
    @{ Enabled = $true; MaxThreads = 'invalid' },
    @{ Enabled = $true; DebugWorkItemIndex = 'invalid' },
    @{ Enabled = $true; DebugInline = 'false' },
    @{ Enabled = $true; ReuseItemSignalGrid = 'false' }
)) {
    $script:sequentialIndices.Clear()
    $script:poolCalls.Clear()
    $invalidPlan = New-TestPlan -Threading $invalidThreading
    $invalidResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $invalidPlan, $context.ItemSignal)
    Assert-True ($invalidResult.Failure()) 'Invalid threading configuration did not fail validation.'
    Assert-True ($script:sequentialIndices.Count -eq 0 -and $script:poolCalls.Count -eq 0) 'Invalid configuration dispatched iterations.'
}

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$missingEnvironmentContext = New-TestContext -SupportParallelism $true -MaxParallelism 3
$null = $missingEnvironmentContext.ConductionSignal.SetPointer(([Graph]::Start('EmptyGraph', $null, $false) | Select-Object -Last 1).GetResult())
$missingEnvironmentPlan = New-TestPlan -Threading @{ Enabled = $true }
$missingEnvironmentResult = $condenser.Invoke($null, 'IteratePhase', $missingEnvironmentContext.ConductionSignal, $missingEnvironmentPlan, $missingEnvironmentContext.ItemSignal)
Assert-True (-not $missingEnvironmentResult.Failure()) 'Missing environment defaults failed.'
Assert-True (($script:sequentialIndices -join ',') -eq '0,1,2,3,4') 'Missing environment did not default to sequential execution.'
Assert-True ($script:poolCalls.Count -eq 0) 'Missing environment unexpectedly started a pool.'

$serialOnlyContext = New-TestContext -SupportParallelism $true -MaxParallelism 3
$serialEnvironment = $serialOnlyContext.ConductionSignal.GetPointer().Grid['EnvironmentDetails'].GetResult()
$serialEnvironment.Config.MaxParallelism = 'invalid'
$serialEnvironment.Config.SupportParallelism = 'invalid'
foreach ($serialSettings in @($null, @{}, @{ Warmup = 'invalid'; DebugInline = 'invalid' }, @{ Enabled = $false; MaxThreads = 'invalid' })) {
    $script:sequentialIndices.Clear()
    $script:poolCalls.Clear()
    $serialOnlyPlan = New-TestPlan -Threading $serialSettings
    $serialOnlyResult = $condenser.Invoke($null, 'IteratePhase', $serialOnlyContext.ConductionSignal, $serialOnlyPlan, $serialOnlyContext.ItemSignal)
    Assert-True (-not $serialOnlyResult.Failure()) 'Serial-only execution inspected unused environment/threading settings.'
    Assert-True (($script:sequentialIndices -join ',') -eq '0,1,2,3,4') 'Serial-only execution skipped or duplicated iterations.'
    Assert-True ($script:poolCalls.Count -eq 0) 'Serial-only execution dispatched workers.'
}

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$singlePlan = New-TestPlan -Threading @{ Enabled = $true }
$singlePlan.Config.IterationArray = @('A')
$singleResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $singlePlan, $context.ItemSignal)
Assert-True (-not $singleResult.Failure()) 'Single-item serial fallback failed.'
Assert-True (($script:sequentialIndices -join ',') -eq '0' -and $script:poolCalls.Count -eq 0) 'Single-item fallback did not execute exactly once.'

Write-Output 'PASS: warmup, parallel dispatch, diagnostics, inline debugging, throttling, grid reuse, validation, and serial-only isolation.'
