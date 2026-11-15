param([Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][string]$InputManifest)
$ErrorActionPreference='Stop'
if(Test-Path $RunRoot){throw 'SOURCE_RUN_ROOT_EXISTS'}
$inputs=Get-Content $InputManifest -Raw|ConvertFrom-Json
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$selected=@($inputs|Where-Object{$_.Path.StartsWith((Join-Path $root 'Src/PowerShell/'),[StringComparison]::OrdinalIgnoreCase)})
if($selected.Count -ne 2){throw 'SOURCE_TWO_INPUTS_REQUIRED'}
foreach($row in $selected){if((Get-FileHash -LiteralPath $row.Path).Hash -ne $row.Sha256){throw 'SOURCE_INPUT_DRIFT'}}
$null=[IO.Directory]::CreateDirectory($RunRoot)
$sg=[IO.Path]::GetFullPath((Join-Path $root '../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1'))
Import-Module $sg -ErrorAction Stop
Import-Module (Join-Path $root 'Src/PowerShell/SovereignTrust.Foundation.psd1') -ErrorAction Stop
& "$PSScriptRoot/CurrentMigration.Focused.ps1" -RunRoot $RunRoot -Selection @{SignalGraph=@{Backend='PowerShell'}}|Out-Null
foreach($row in $selected){if((Get-FileHash -LiteralPath $row.Path).Hash -ne $row.Sha256){throw 'SOURCE_INPUT_DRIFT_AFTER_CHECK'}}
[ordered]@{Scope='Read-only focused current two files; no original runtime/bootstrap/provider execution';SourceFiles=$selected;SignalGraphPath=(Get-Module SignalGraph).Path;FoundationPath=(Get-Module SovereignTrust.Foundation).Path;ProcessId=$PID;Command=[Environment]::GetCommandLineArgs()}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $RunRoot 'source-provenance.json')
$r=Get-Content (Join-Path $RunRoot migration-focused.json) -Raw|ConvertFrom-Json
"$($r.PassCount)/$($r.FailCount)/$($r.Total) skip0"
