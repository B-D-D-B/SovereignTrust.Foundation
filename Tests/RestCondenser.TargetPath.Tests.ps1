using module ../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

$ErrorActionPreference = 'Stop'
class RestCondenser {
    [Signal] ResolveBearerToken([Signal]$signal, [object]$plan, [bool]$refresh) {
        $result = [Signal]::Start('FixtureToken') | Select-Object -Last 1
        $result.SetResult('fresh-token') | Out-Null
        return $result
    }
}
. "$PSScriptRoot/../Src/PowerShell/Utilities/Adapters/Condenser/Rest/Invoke-RestCondenserCore.ps1"

function Resolve-PathFromDictionary {
    param($Dictionary, [string]$Path, $Default, $SignalLevel)
    $result = [Signal]::Start("Fixture:$Path") | Select-Object -Last 1
    $name = $Path.Split('.')[-1]
    $property = $Dictionary.Config.PSObject.Properties[$name]
    if ($null -ne $property -and $null -ne $property.Value) { $result.SetResult($property.Value) | Out-Null }
    elseif ($PSBoundParameters.ContainsKey('Default')) { $result.SetResult($Default) | Out-Null }
    return $result
}
function Add-PathToDictionary {
    param($Dictionary, [string]$Path, $Value)
    $name = $Path.Split('.')[-1]
    $Dictionary.Config | Add-Member -NotePropertyName $name -NotePropertyValue $Value -Force
}

$script:failDownload = $false
$script:httpCalls = 0
$script:responses = @()
function Invoke-RestMethod {
    param($Uri, $Method, $Headers, $OutFile)
    $script:httpCalls++
    if ($script:responses.Count -ge $script:httpCalls) {
        $response = $script:responses[$script:httpCalls - 1]
        if ($response -eq 'auth') {
            [IO.File]::WriteAllBytes($OutFile, [byte[]]@(9))
            throw '401 (Unauthorized)'
        }
        if ($response -eq 'partial-fail') {
            [IO.File]::WriteAllBytes($OutFile, [byte[]]@(9))
            throw 'Simulated transport failure'
        }
    }
    if ($script:failDownload) { throw 'Simulated download failure' }
    [IO.File]::WriteAllBytes($OutFile, [byte[]]@(0, 255, 13, 10, 128))
}
function Assert-True([bool]$condition, [string]$message) { if (-not $condition) { throw $message } }

$root = Join-Path ([IO.Path]::GetTempPath()) ('st-rest-target-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$pass = 0
try {
    $target = Join-Path $root 'target.bin'
    [IO.File]::WriteAllBytes($target, [byte[]]@(7, 8))
    $signal = [Signal]::Start('RestTargetTest') | Select-Object -Last 1
    $rest = [RestCondenser]::new()
    function Invoke-TestRead($config) {
        $plan = [pscustomobject]@{ Config = [pscustomobject]$config }
        Invoke-RestCondenserCore -RestCondenser $rest -Activity 'Get' -Slot 'Test' -Signal $signal -ItemSignal $signal -Plan $plan | Select-Object -Last 1
    }
    $base = @{ Uri = 'https://example.invalid/blob'; Method = 'Get'; TargetPath = $target; Headers = @{} }
    $ok = Invoke-TestRead $base
    Assert-True ($ok.Success() -and $ok.GetResult().Response -eq [IO.Path]::GetFullPath($target)) 'completed download did not return final path'
    Assert-True ([Linq.Enumerable]::SequenceEqual([byte[]]@(0, 255, 13, 10, 128), [byte[]][IO.File]::ReadAllBytes($target))) 'download changed binary bytes'
    $pass += 2

    [IO.File]::WriteAllBytes($target, [byte[]]@(7, 8))
    $script:failDownload = $true
    $script:httpCalls = 0
    $failed = Invoke-TestRead $base
    Assert-True ($failed.Failure() -and -not $failed.HasResult()) 'failed download reported success'
    Assert-True ($script:httpCalls -eq 3) 'download retry bound changed'
    Assert-True ([Linq.Enumerable]::SequenceEqual([byte[]]@(7, 8), [byte[]][IO.File]::ReadAllBytes($target))) 'failed download changed target'
    Assert-True (@(Get-ChildItem -LiteralPath $root -Filter '.st-read-*').Count -eq 0) 'temporary download remained'
    $pass += 4

    $script:failDownload = $false
    foreach ($case in @(
        @{ Responses = @('auth', 'partial-fail', 'partial-fail'); Calls = 3; Failure = $true },
        @{ Responses = @('auth', 'auth'); Calls = 2; Failure = $true },
        @{ Responses = @('auth', 'success'); Calls = 2; Failure = $false }
    )) {
        [IO.File]::WriteAllBytes($target, [byte[]]@(7, 8))
        $script:responses = $case.Responses
        $script:httpCalls = 0
        $result = Invoke-TestRead $base
        Assert-True ($script:httpCalls -eq $case.Calls) "auth retry used $script:httpCalls GET calls instead of $($case.Calls)"
        Assert-True ($result.Failure() -eq $case.Failure) 'auth retry returned wrong failure state'
        if ($case.Failure) {
            Assert-True (-not $result.HasResult() -and [Linq.Enumerable]::SequenceEqual([byte[]]@(7, 8), [byte[]][IO.File]::ReadAllBytes($target))) 'failed auth retry changed target or reported result'
        }
        else {
            Assert-True ($result.GetResult().Response -eq [IO.Path]::GetFullPath($target) -and [Linq.Enumerable]::SequenceEqual([byte[]]@(0, 255, 13, 10, 128), [byte[]][IO.File]::ReadAllBytes($target))) 'successful auth retry did not commit downloaded bytes'
        }
        Assert-True (@(Get-ChildItem -LiteralPath $root -Filter '.st-read-*').Count -eq 0) 'auth retry left a partial temp file'
        $pass += 4
    }
    $script:responses = @()

    foreach ($bad in @(
        @{ Uri = 'https://example.invalid/blob'; Method = 'Get'; TargetPath = ''; Headers = @{} },
        @{ Uri = 'https://example.invalid/blob'; Method = 'Get'; TargetPath = 'relative.bin'; Headers = @{} },
        @{ Uri = 'https://example.invalid/blob'; Method = 'Post'; TargetPath = $target; Headers = @{} },
        @{ Uri = 'https://example.invalid/blob'; Method = 'Get'; TargetPath = $target; ReturnHttpStatus = $true; Headers = @{} }
    )) {
        $script:httpCalls = 0
        $result = Invoke-TestRead $bad
        Assert-True ($result.Failure() -and -not $result.HasResult() -and $script:httpCalls -eq 0) 'invalid target reached HTTP'
        $pass++
    }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
"PASS $pass/$pass REST target assertions"
