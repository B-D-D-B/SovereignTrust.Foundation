using module ../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

$ErrorActionPreference = 'Stop'
$foundationRoot = Join-Path $PSScriptRoot '../Src/PowerShell'
. "$foundationRoot/Classes/Adapters/MappedStorageAdapter.ps1"

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

$script:resolutionCount = 0
function Resolve-PathFromDictionary {
    param($Dictionary, [string]$Path)
    $script:resolutionCount++
    throw 'Provider resolution reached.'
}

$adapter = [MappedStorageAdapter]::new()
$signal = [Signal]::Start('StorageActivity.Test') | Select-Object -Last 1

foreach ($activity in @($null, '', 'ReadBatch', 'Remove')) {
    $result = $adapter.Invoke('Fixture', $activity, $signal, $null, $signal) | Select-Object -Last 1
    Assert-True ($result.Failure()) "Invalid activity '$activity' did not fail."
    Assert-True ($script:resolutionCount -eq 0) "Invalid activity '$activity' reached provider resolution."
}

foreach ($activity in @('Read', 'Write', 'Delete', 'Exists', 'List', 'rEaD')) {
    try {
        $null = $adapter.Invoke('Fixture', $activity, $signal, $null, $signal)
        throw "Allowed activity '$activity' did not reach provider resolution."
    }
    catch {
        Assert-True ($_.Exception.Message -match 'Provider resolution reached') "Allowed activity '$activity' was rejected before provider resolution."
    }
}
Assert-True ($script:resolutionCount -eq 6) 'An allowed activity did not reach provider resolution exactly once.'

Write-Output 'PASS: MappedStorageAdapter rejects unsupported activities at Invoke entry and admits allowed activities.'
