using module ../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

$ErrorActionPreference = 'Stop'
class Conductor {}

$root = Join-Path $PSScriptRoot '../Src/PowerShell/Classes/Adapters'
. (Join-Path $root 'MappedConductionAdapter.ps1')
class MappedCondenserAdapter {}
. (Join-Path $root 'Condenser/ConductionCondenser.ps1')

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

$script:mapped = [MappedConductionAdapter]::new()
$script:coreCount = 0
function Invoke-MappedAdapter {
    param($Signal, $ItemSignal, $Plan, $Adapter, $Activity)
    if ($Adapter -cne 'Conduction.ST') { throw "Unexpected route: $Adapter" }
    return $script:mapped.Invoke('ST', $Activity, $Signal, $Plan, $ItemSignal)
}
function Invoke-MappedAdapterCore {
    param($MappedAdapterSignal, $ConductionSignal, $Slot, $Activity, $Plan, $ItemSignal)
    $script:coreCount++
    if ($Activity -cne 'ST') { throw "Unexpected activity: $Activity" }
    $result = [Signal]::Start('ConductionActivityBridge.Core') | Select-Object -Last 1
    $result.SetResult('ran') | Out-Null
    return $result
}

$signal = [Signal]::Start('ConductionActivityBridge.Signal') | Select-Object -Last 1
$condenser = [ConductionCondenser]::new()
$result = $condenser.Invoke('Fixture', 'ST', $signal, $null, $signal) | Select-Object -Last 1
Assert-True (-not $result.Failure() -and $script:coreCount -eq 1) 'Conduction.ST did not cross the mapped activity guard.'

Write-Output 'PASS: ST activity crosses the condenser and mapped conduction Invoke guards.'
