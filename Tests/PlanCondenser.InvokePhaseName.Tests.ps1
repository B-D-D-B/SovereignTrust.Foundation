using module ../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

class Conductor {}
class MappedCondenserAdapter {}

$foundationRoot = Join-Path $PSScriptRoot '../Src/PowerShell'
. "$foundationRoot/Wrappers/Adapters/Invoke-CondenserAdapter.ps1"
. "$foundationRoot/Utilities/Adapters/Condenser/Plan/Resolve-ClonePlan.ps1"
. "$foundationRoot/Utilities/Adapters/Condenser/Plan/Invoke-PlanPhase.ps1"
. "$foundationRoot/Classes/Adapters/Condenser/PlanCondenser.ps1"

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

$script:generatedPhase = $null
$script:memoryCalls = 0
function Invoke-CondenserAdapter {
    param($Slot, $Activity, $Signal, $Plan, $ItemSignal)
    $result = [Signal]::Start("Fixture.$Slot.$Activity") | Select-Object -Last 1
    if ($Slot -ceq 'Hydration') {
        $result.SetResult($ItemSignal.GetJacketResult())
    } elseif ($Slot -ceq 'Memory' -and $Activity -ceq 'Generate') {
        $script:generatedPhase = $Plan
        $script:memoryCalls++
        $registered = $ItemSignal.GetPointer().RegisterResultAsSignal('PhaseEffect', 'controlled') | Select-Object -Last 1
        if ($registered.Failure()) { return $result.LogCritical('Could not register fixture effect.') }
        $result.SetResult($true)
    } else {
        return $result.LogCritical("Unexpected downstream adapter: $Slot/$Activity")
    }
    return $result
}

$graph = ([Graph]::Start('PhaseNameGraph', $null, $false) | Select-Object -Last 1).GetResult()
$conduction = [Signal]::Start('Conduction') | Select-Object -Last 1
$null = $conduction.SetPointer($graph)
$item = [Signal]::Start('Item') | Select-Object -Last 1
$null = $item.SetPointer($graph)
$item.SetResult(@([pscustomobject]@{ Name = 'InnerStep'; Activity = 'Fixture' }))
$plan = [pscustomobject]@{
    Name = 'NamedParentPhase'
    Path = '@'
    Config = [pscustomobject]@{
        Iteration = 0
        PreventReclone = $false
        Break = $false
        SkipRename = $true
    }
}

Start-STExecutionTrace -Context @{
    RunId = 'phase-name'; CaseId = 'strict-mode'; CorrelationId = 'fixture'
    Sources = @{ Plan = @{ Path = 'fixture'; Sha256 = ('A' * 64); Location = 'NamedParentPhase' } }
}
try {
    $result = [PlanCondenser]::new().Invoke('', 'InvokePhase', $conduction, $plan, $item)
    Assert-True (-not $result.Failure()) 'Named child InvokePhase failed.'
    Assert-True ($script:memoryCalls -eq 1) 'Real Invoke-PlanPhase did not call Memory Generate once.'
    Assert-True ($null -ne $script:generatedPhase -and $script:generatedPhase.Name -ceq $plan.Name) 'Child phase did not preserve the parent Name.'
    Assert-True (@($script:generatedPhase.Steps).Count -eq 1) 'Child phase lost its inner step.'
    Assert-True ($graph.Grid.Contains('PhaseEffect') -and $graph.Grid['PhaseEffect'].GetResult() -ceq 'controlled') 'Child phase did not preserve the item graph effect.'
    $trace = Get-STExecutionTrace
    Assert-True ($trace.Complete -and @($trace.Rows).Count -eq 2) 'Plan and child phase trace did not finish.'
    $child = @($trace.Rows | Where-Object { $_.BoundaryKind -ceq 'Phase' })
    Assert-True ($child.Count -eq 1 -and $child[0].BoundaryName -ceq $plan.Name -and $child[0].Status -ceq 'Succeeded') 'Child phase trace name or terminal status differed.'
} finally { Stop-STExecutionTrace }

Write-Output 'PASS: named InvokePhase child, real phase function, item graph effect and completed trace.'
