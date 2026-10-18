using module ../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

class MappedStorageAdapter {}

$foundationRoot = Join-Path $PSScriptRoot '../Src/PowerShell'
. "$foundationRoot/Utilities/Adapters/Storage/Invoke-EmbeddedFileSystem_WriteObject.ps1"
. "$foundationRoot/Classes/Adapters/Storage/Storage_EmbeddedFileSystem.ps1"

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Resolve-PathFromDictionary {
    param($Dictionary, [string]$Path, $Default, $SignalLevel)
    $result = [Signal]::Start("Fixture.Resolve:$Path") | Select-Object -Last 1
    if ($Path -eq '$.%.@.Addresses') {
        $result.SetResult(@($script:testRoot))
    }
    elseif ($Path -eq 'VirtualPath') {
        $result.SetResult($Dictionary.VirtualPath)
    }
    elseif ($Path -eq 'Config.SignalLevel') {
        $result.SetResult('Critical')
    }
    elseif ($Path -in @('Config.Content', 'Config.SourcePath')) {
        $propertyName = $Path.Split('.')[1]
        $property = $Dictionary.Config.PSObject.Properties[$propertyName]
        if ($null -ne $property -and $null -ne $property.Value) {
            $result.SetResult($property.Value)
        }
    }
    return $result
}

function Invoke-Write([string]$virtualPath, [object]$config) {
    $adapter = [Storage_EmbeddedFileSystem]::new()
    $adapter.Signal = [Signal]::Start('Fixture.Embedded') | Select-Object -Last 1
    $plan = [pscustomobject]@{ VirtualPath = $virtualPath; Config = $config }
    return $adapter.Invoke('LocalContent', 'Write', $adapter.Signal, $plan, $adapter.Signal)
}

$script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("st-embedded-source-" + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $script:testRoot
$pass = 0
try {
    $source = Join-Path $script:testRoot 'fixture.bin'
    $bytes = [byte[]]@(0, 255, 13, 10, 128, 1)
    [System.IO.File]::WriteAllBytes($source, $bytes)

    $copied = Invoke-Write 'out/copied.bin' ([pscustomobject]@{ Content = $null; SourcePath = $source })
    Assert-True (-not $copied.Failure() -and $copied.HasResult()) 'source dispatch failed'
    Assert-True ([System.Linq.Enumerable]::SequenceEqual([byte[]]$bytes, [byte[]][System.IO.File]::ReadAllBytes((Join-Path $script:testRoot 'out/copied.bin')))) 'source bytes changed'
    $pass += 2

    $sourceOnly = Invoke-Write 'out/source-only.bin' ([pscustomobject]@{ SourcePath = $source })
    Assert-True (-not $sourceOnly.Failure() -and $sourceOnly.HasResult()) 'SourcePath-only dispatch failed'
    Assert-True ([System.Linq.Enumerable]::SequenceEqual([byte[]]$bytes, [byte[]][System.IO.File]::ReadAllBytes((Join-Path $script:testRoot 'out/source-only.bin')))) 'SourcePath-only bytes changed'
    $pass += 2

    $existing = Join-Path $script:testRoot 'existing.bin'
    [System.IO.File]::WriteAllBytes($existing, $bytes)
    $missing = Invoke-Write 'existing.bin' ([pscustomobject]@{ Content = $null; SourcePath = (Join-Path $script:testRoot 'missing.bin') })
    Assert-True ($missing.Failure() -and -not $missing.HasResult() -and [System.Linq.Enumerable]::SequenceEqual([byte[]]$bytes, [byte[]][System.IO.File]::ReadAllBytes($existing))) 'missing source changed destination'
    $pass++

    $missingFresh = Invoke-Write 'missing-parent/fresh.bin' ([pscustomobject]@{ SourcePath = (Join-Path $script:testRoot 'missing.bin') })
    Assert-True ($missingFresh.Failure() -and -not $missingFresh.HasResult() -and -not (Test-Path -LiteralPath (Join-Path $script:testRoot 'missing-parent'))) 'missing source created destination directory'
    $pass++

    $directorySource = Invoke-Write 'existing.bin' ([pscustomobject]@{ SourcePath = $script:testRoot })
    Assert-True ($directorySource.Failure() -and -not $directorySource.HasResult() -and [System.Linq.Enumerable]::SequenceEqual([byte[]]$bytes, [byte[]][System.IO.File]::ReadAllBytes($existing))) 'directory source changed destination'
    $pass++

    $same = Invoke-Write 'fixture.bin' ([pscustomobject]@{ Content = $null; SourcePath = $source })
    Assert-True ($same.Failure() -and -not $same.HasResult() -and [System.Linq.Enumerable]::SequenceEqual([byte[]]$bytes, [byte[]][System.IO.File]::ReadAllBytes($source))) 'same source and destination was not rejected'
    $pass++

    $absent = Invoke-Write 'no-input/file.bin' ([pscustomobject]@{})
    Assert-True ($absent.Failure() -and -not $absent.HasResult() -and -not (Test-Path -LiteralPath (Join-Path $script:testRoot 'no-input'))) 'missing inputs created destination'
    $pass++

    foreach ($content in @('', $false, 0)) {
        $name = if ($content -is [bool]) { 'false' } elseif ($content -is [int]) { 'zero' } else { 'empty' }
        $result = Invoke-Write "content/$name.txt" ([pscustomobject]@{ Content = $content; SourcePath = $source })
        Assert-True (-not $result.Failure() -and $result.HasResult()) "content precedence failed: $name"
        Assert-True ([System.IO.File]::ReadAllText((Join-Path $script:testRoot "content/$name.txt")) -ceq [string]$content) "content value changed: $name"
        $pass += 2
    }

    $json = Invoke-Write 'content/object.json' ([pscustomobject]@{ Content = [pscustomobject]@{ Data = 'Test' }; SourcePath = $null })
    Assert-True (-not $json.Failure() -and (([System.IO.File]::ReadAllText((Join-Path $script:testRoot 'content/object.json')) | ConvertFrom-Json).Data -ceq 'Test')) 'JSON content regression'
    $pass++

    $text = Invoke-Write 'content/plain.txt' ([pscustomobject]@{ Content = 'plain text'; SourcePath = $null })
    Assert-True (-not $text.Failure() -and $text.HasResult() -and [System.IO.File]::ReadAllText((Join-Path $script:testRoot 'content/plain.txt')) -ceq 'plain text') 'plain text content regression'
    $pass++
}
finally {
    Remove-Item -LiteralPath $script:testRoot -Recurse -Force
}

"PASS $pass/$pass EmbeddedFileSystem offline assertions"
