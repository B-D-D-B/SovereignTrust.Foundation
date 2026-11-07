using module ../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

$ErrorActionPreference = 'Stop'
$adapterRoot = Join-Path $PSScriptRoot '../Src/PowerShell/Classes/Adapters'
$names = @(
    'MappedConductionAdapter', 'MappedDataAdapter',
    'MappedIntelligenceAdapter', 'MappedNetworkAdapter', 'MappedQueueAdapter',
    'MappedSatelliteAdapter', 'MappedSessionAdapter', 'MappedStorageAdapter',
    'MappedTokenAdapter', 'MappedUtilityAdapter'
)
foreach ($name in $names) { . (Join-Path $adapterRoot "$name.ps1") }
. (Join-Path $adapterRoot 'MappedCondenserAdapter.ps1')

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

$script:dispatchCount = 0
$script:lastActivity = $null
function Invoke-MappedAdapterCore {
    param($MappedAdapterSignal, $ConductionSignal, $Slot, $Activity, $Plan, $ItemSignal)
    $script:dispatchCount++
    $script:lastActivity = $Activity
    $result = [Signal]::Start('ActivityFixture.Core') | Select-Object -Last 1
    $result.SetResult('accepted') | Out-Null
    return $result
}
function Invoke-MappedTokenAdapter {
    param($MappedAdapter, $Slot, $Activity, $Signal, $Plan, $ItemSignal)
    $script:dispatchCount++
    $result = [Signal]::Start('ActivityFixture.Token') | Select-Object -Last 1
    $result.SetResult('accepted') | Out-Null
    return $result
}
function Resolve-PathFromDictionary {
    param($Dictionary, $Path)
    $script:dispatchCount++
    throw 'ActivityFixture reached provider resolution.'
}

$signal = [Signal]::Start('ActivityFixture.Signal') | Select-Object -Last 1
foreach ($name in $names) {
    $path = Join-Path $adapterRoot "$name.ps1"
    $source = Get-Content $path -Raw
    $header = [regex]::Match($source, '(?s)^\s*<#(?<text>.*?)#>').Groups['text'].Value
    Assert-True ($header -match 'ActivityScope: AdapterAgnostic') "$name lacks an adapter agnostic contract."
    $activities = @([regex]::Matches($header, '(?m)^- ([A-Za-z][A-Za-z0-9]*): .+$') | ForEach-Object { $_.Groups[1].Value })
    Assert-True ($activities.Count -gt 0) "$name has no documented activities."
    $adapter = New-Object -TypeName $name

    foreach ($activity in @($null, '', 'UnsupportedActivity')) {
        $script:dispatchCount = 0
        $result = $adapter.Invoke('Fixture', $activity, $signal, $null, $signal) | Select-Object -Last 1
        Assert-True ($result.Failure()) "$name accepted unsupported activity '$activity'."
        Assert-True ($script:dispatchCount -eq 0) "$name dispatched unsupported activity '$activity'."
    }
    if ($name -ceq 'MappedIntelligenceAdapter') {
        foreach ($removedActivity in @('SendMessageOriginal','sendmessageoriginal')) {
            $script:dispatchCount = 0
            $removed = $adapter.Invoke('Fixture', $removedActivity, $signal, $null, $signal) | Select-Object -Last 1
            Assert-True ($removed.Failure() -and -not $removed.HasResult()) "Mapped intelligence accepted '$removedActivity'."
            Assert-True ($script:dispatchCount -eq 0) "Mapped intelligence dispatched '$removedActivity'."
        }
    }
    if ($header -match 'ActivityComparison: CaseSensitive') {
        $script:dispatchCount = 0
        $caseMismatch = $adapter.Invoke('Fixture', $activities[0].ToLowerInvariant(), $signal, $null, $signal) | Select-Object -Last 1
        Assert-True ($caseMismatch.Failure() -and $script:dispatchCount -eq 0) "$name accepted an activity with different casing."
    }

    foreach ($activity in $activities) {
        $script:dispatchCount = 0
        try {
            $null = $adapter.Invoke('Fixture', $activity, $signal, $null, $signal)
        }
        catch {
            Assert-True ($_.Exception.Message -match 'ActivityFixture reached provider resolution') "$name rejected documented activity '$activity': $_"
        }
        Assert-True ($script:dispatchCount -eq 1) "$name did not dispatch documented activity '$activity'."
    }
    if ($header -match 'ActivityForwarding: Canonical') {
        $script:dispatchCount = 0
        $null = $adapter.Invoke('Fixture', $activities[0].ToLowerInvariant(), $signal, $null, $signal)
        Assert-True ($script:dispatchCount -eq 1 -and $script:lastActivity -ceq $activities[0]) "$name did not forward canonical activity casing."
    }
}

$mappedSource = Get-Content (Join-Path $adapterRoot 'MappedCondenserAdapter.ps1') -Raw
Assert-True ($mappedSource -match 'ActivityScope: None') 'MappedCondenserAdapter declares an activity scope.'
Assert-True ($mappedSource -match '\$consdenser\.Invoke\(\$Slot, \$Activity,') 'MappedCondenserAdapter does not forward the original Activity.'
$script:dispatchCount = 0
$mapped = New-Object -TypeName MappedCondenserAdapter
$null = $mapped.Invoke('Fixture', 'UnlistedProviderActivity', $signal, $null, $signal)
Assert-True ($script:dispatchCount -eq 1) 'MappedCondenserAdapter rejected an activity before provider resolution.'

$script:forwardedUtility = [System.Collections.Generic.List[string]]::new()
$script:fakeUtility = [pscustomobject]@{}
$script:fakeUtility | Add-Member -MemberType ScriptMethod -Name Invoke -Value {
    param($slot,$activity,$conduction,$plan,$item)
    $script:forwardedUtility.Add("$slot/$activity")
    $answer = [Signal]::Start('ActivityFixture.UtilityForward') | Select-Object -Last 1
    $answer.SetResult('forwarded') | Out-Null
    return $answer
}
function Resolve-PathFromDictionary {
    param($Dictionary,$Path,$SignalLevel,$Default)
    $answer = [Signal]::Start('ActivityFixture.Resolve') | Select-Object -Last 1
    if ($Path -eq '*.#.Media') { $answer.SetResult($script:fakeUtility) | Out-Null }
    elseif ($Path -eq 'Config.VirtualPath') { $answer.SetResult('Media') | Out-Null }
    return $answer
}
function Resolve-MappedAdapter {
    param($AdapterSignal,$Signal,$ConductionContext)
    $answer = [Signal]::Start('ActivityFixture.ResolveMapped') | Select-Object -Last 1
    $answer.SetResult($script:fakeUtility) | Out-Null
    return $answer
}
$utility = [MappedUtilityAdapter]::new()
$utility.Signal = [Signal]::Start('ActivityFixture.Utility') | Select-Object -Last 1
$utilityPlan = [pscustomobject]@{ Config=[pscustomobject]@{VirtualPath='Media'} }
foreach ($activity in @('MaterializeGeneratedImage','ValidateVisionSelection','FinalizeGeneratedImage')) {
    $forwarded = $utility.Invoke('Media',$activity,$signal,$utilityPlan,$signal) | Select-Object -Last 1
    Assert-True (-not $forwarded.Failure() -and $forwarded.HasResult() -and
        $forwarded.GetResult() -ceq 'forwarded' -and $script:forwardedUtility[-1] -ceq "Media/$activity") "$activity did not forward into the fake Utility provider."
}

Write-Output 'PASS: mapped activity guards reject before dispatch; condenser mapping forwards arbitrary activities to provider resolution.'
