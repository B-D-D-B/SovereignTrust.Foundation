using module ../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

$ErrorActionPreference = 'Stop'
$foundationRoot = Join-Path $PSScriptRoot '../Src/PowerShell'
. "$foundationRoot/Utilities/Graph/Export-STSignalGraphSnapshot.ps1"
. "$foundationRoot/Utilities/Graph/Import-STSignalGraphSnapshot.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$sourceGraph = ([Graph]::Start('SourceGraph', $null, $false) | Select-Object -Last 1).GetResult()
$sourceValue = [PSCustomObject]@{ Name = 'LaunchValue'; Nested = [PSCustomObject]@{ Count = 1 } }
$sourceMember = [Signal]::Start('SourceMember') | Select-Object -Last 1
$sourceMember.SetResult($sourceValue)
$null = $sourceGraph.RegisterSignal('SharedValue', $sourceMember)
$sourceItem = [Signal]::Start('SourceItem') | Select-Object -Last 1
$null = $sourceItem.SetPointer($sourceGraph)
$sourceItem.SetResult([PSCustomObject]@{ Item = 'LaunchItem' })

$exportSignal = Export-STSignalGraphSnapshot -ItemSignal $sourceItem | Select-Object -Last 1
Assert-True (-not $exportSignal.Failure() -and $exportSignal.HasResult()) 'Graph snapshot export failed.'
$sourceValue.Name = 'ParentChangedAfterLaunch'
$sourceValue.Nested.Count = 2

$targetConduction = [Signal]::Start('TargetConduction') | Select-Object -Last 1
$targetGraph = ([Graph]::Start('TargetGraph', $targetConduction, $false) | Select-Object -Last 1).GetResult()
$null = $targetConduction.SetPointer($targetGraph)
$environmentMember = [Signal]::Start('EnvironmentDetails') | Select-Object -Last 1
$environmentMember.SetResult('WorkerEnvironment')
$null = $targetGraph.RegisterSignal('EnvironmentDetails', $environmentMember)

$importSignal = Import-STSignalGraphSnapshot `
    -SnapshotJson ([string]$exportSignal.GetResult()) `
    -ConductionSignal $targetConduction |
    Select-Object -Last 1
Assert-True (-not $importSignal.Failure() -and $importSignal.HasResult()) 'Graph snapshot import failed.'
$workerItem = $importSignal.GetResult()
$workerValue = $workerItem.GetPointer().Grid['SharedValue'].GetResult()

Assert-True ($workerValue.Name -eq 'LaunchValue' -and $workerValue.Nested.Count -eq 1) 'Worker snapshot changed with the parent graph.'
Assert-True (-not [object]::ReferenceEquals($workerValue, $sourceValue)) 'Worker snapshot reused the parent result object.'
Assert-True ($workerItem.GetPointer().Grid['EnvironmentDetails'].GetResult() -eq 'WorkerEnvironment') 'Snapshot import overwrote the worker environment.'
Assert-True ($workerItem.GetResult().Item -eq 'LaunchItem') 'ItemSignal result was not preserved in the snapshot.'

Write-Output 'PASS: graph snapshots are isolated, typed, importable, and preserve worker environment registrations.'
