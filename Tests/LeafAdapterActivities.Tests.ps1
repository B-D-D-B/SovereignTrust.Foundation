using module ../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

$ErrorActionPreference = 'Stop'
class Conductor {}
class MappedCondenserAdapter {}
class MappedStorageAdapter {}
class MappedTokenAdapter {}

$root = Join-Path $PSScriptRoot '../Src/PowerShell/Classes/Adapters'
$paths = @(
    'Condenser/ConductionCondenser.ps1', 'Condenser/ConduitCondenser.ps1',
    'Condenser/FabCondenser.ps1', 'Condenser/FormatCondenser.ps1',
    'Condenser/HydrationCondenser.ps1', 'Condenser/MapCondenser.ps1',
    'Condenser/MemoryCondenser.ps1', 'Condenser/MergeCondenser.ps1',
    'Condenser/PlanCondenser.ps1', 'Condenser/RestCondenser.ps1',
    'Condenser/TokenCondenser.ps1', 'Condenser/TransformCondenser.ps1',
    'Storage/Storage_EmbeddedFileSystem.ps1',
    'Token/Token_Conduction.ps1', 'Token/Token_Dynamic.ps1',
    'Token/Token_Environment.ps1', 'Token/Token_Formatter.ps1',
    'Token/Token_Generator.ps1', 'Token/Token_Memory.ps1',
    'Token/Token_Navigator.ps1', 'Token/Token_Storage.ps1',
    'Token/Token_System.ps1'
)
foreach ($path in $paths) { . (Join-Path $root $path) }

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

$signal = [Signal]::Start('LeafActivity.Test') | Select-Object -Last 1
foreach ($path in $paths) {
    $source = Get-Content (Join-Path $root $path) -Raw
    $name = [System.IO.Path]::GetFileNameWithoutExtension($path)
    $header = [regex]::Match($source, '(?s)<#\s*Class: ' + [regex]::Escape($name) + '(?<text>.*?)#>').Groups['text'].Value
    Assert-True ($header -match 'ActivityScope: AdapterAgnostic') "$name lacks an activity contract."
    $documented = @([regex]::Matches($header, '(?m)^- ([A-Za-z][A-Za-z0-9]*): .+$') | ForEach-Object { $_.Groups[1].Value })
    Assert-True ($documented.Count -gt 0) "$name has no documented activities."
    $guard = [regex]::Match($source, '(?s)if \(\$Activity -notin @\((?<values>.*?)\)\)')
    Assert-True ($guard.Success) "$name has no Invoke activity guard."
    $allowed = @([regex]::Matches($guard.Groups['values'].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
    Assert-True (($allowed -join ',') -ceq ($documented -join ',')) "$name activity guard differs from its header."
    if ($path -like 'Condenser/*') {
        $catalogPath = Join-Path $root "Catalog/Condensers/$name.json"
        $catalog = Get-Content $catalogPath -Raw | ConvertFrom-Json
        $catalogActivities = @($catalog.activities | ForEach-Object { $_.name })
        Assert-True (($allowed -join ',') -ceq ($catalogActivities -join ',')) "$name activity guard differs from its catalog."
        foreach ($activity in $catalogActivities) {
            Assert-True (-not ($activity.ToLowerInvariant() -notin $allowed)) "$name rejected declared activity '$activity' in lowercase."
            Assert-True (-not ($activity.ToUpperInvariant() -notin $allowed)) "$name rejected declared activity '$activity' in uppercase."
        }
    }
    $adapter = New-Object -TypeName $name
    $result = $adapter.Invoke('Fixture', 'UnsupportedActivity', $signal, $null, $signal) | Select-Object -Last 1
    Assert-True ($result.Failure()) "$name accepted an unsupported activity."
}

$graphCatalog = Get-Content (Join-Path $root 'Catalog/Condensers/GraphCondenser.json') -Raw | ConvertFrom-Json
$graphSource = Get-Content (Join-Path $root 'Condenser/GraphCondenser.ps1') -Raw
$graphInvoke = [regex]::Match($graphSource, '\[Signal\]\s+Invoke\((?<parameters>[^)]*)\)')
Assert-True (@($graphCatalog.activities).Count -eq 0) 'GraphCondenser catalog declares activities.'
Assert-True ($graphInvoke.Success -and $graphInvoke.Groups['parameters'].Value -notmatch '\$Activity') 'GraphCondenser has Activity dispatch.'

Write-Output 'PASS: leaf guards match headers and condenser catalogs, reject unsupported activities, and exempt GraphCondenser.'
