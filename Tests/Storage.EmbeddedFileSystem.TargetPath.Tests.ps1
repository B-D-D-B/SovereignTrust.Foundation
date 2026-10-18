using module ../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../Src/PowerShell/Utilities/Adapters/Storage/Invoke-EmbeddedFileSystem_ReadObject.ps1"

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('st-target-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$pass = 0
try {
    $source = Join-Path $root 'source.bin'
    $target = Join-Path $root 'target.bin'
    $bytes = [byte[]]@(0, 255, 13, 10, 128, 1)
    [IO.File]::WriteAllBytes($source, $bytes)
    [IO.File]::WriteAllBytes($target, [byte[]]@(7, 8))
    $signal = [Signal]::Start('TargetTest') | Select-Object -Last 1

    $read = Invoke-EmbeddedFileSystem_ReadObject -Signal $signal -VirtualPath 'source.bin' -Addresses @($root) -TargetPath $target -TargetPathProvided
    Assert-True ($read.Success() -and $read.GetResult() -eq [IO.Path]::GetFullPath($target)) 'target result path incorrect'
    Assert-True ([Linq.Enumerable]::SequenceEqual($bytes, [byte[]][IO.File]::ReadAllBytes($target))) 'binary copy changed bytes'
    $pass += 2

    foreach ($case in @(
        @{ VirtualPath = 'missing.bin'; Target = $target; Message = 'missing source' },
        @{ VirtualPath = 'source.bin'; Target = $source; Message = 'source alias' },
        @{ VirtualPath = 'source.bin'; Target = ''; Message = 'blank target' },
        @{ VirtualPath = 'source.bin'; Target = 'relative.bin'; Message = 'relative target' }
    )) {
        $failed = Invoke-EmbeddedFileSystem_ReadObject -Signal $signal -VirtualPath $case.VirtualPath -Addresses @($root) -TargetPath $case.Target -TargetPathProvided
        Assert-True ($failed.Failure() -and -not $failed.HasResult()) "$($case.Message) returned success"
        $pass++
    }
    Assert-True ([Linq.Enumerable]::SequenceEqual($bytes, [byte[]][IO.File]::ReadAllBytes($target))) 'failed copy changed target'
    Assert-True (@(Get-ChildItem -LiteralPath $root -Filter '.st-read-*').Count -eq 0) 'temporary target remained'
    $pass += 2

    $legacy = Invoke-EmbeddedFileSystem_ReadObject -Signal $signal -VirtualPath 'source.bin' -Addresses @($root)
    Assert-True ($legacy.Success() -and $legacy.HasResult()) 'legacy read failed'
    $pass++
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
"PASS $pass/$pass EmbeddedFileSystem target assertions"
