[CmdletBinding()]
param([Parameter(Mandatory)][string]$FoundationManifest,
      [Parameter(Mandatory)][string]$SignalGraphManifest,
      [Parameter(Mandatory)][string]$OutputPath,[switch]$IncludeAdapterEntryPoints)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../../Src/PowerShell/Bootstrap/STFoundationSelection.ps1"
function Get-ModulePacket([string]$Manifest) {
    $manifest=Resolve-STSelectionPath $Manifest
    $root=Split-Path $manifest
    $data=Import-PowerShellDataFile -LiteralPath $manifest
    $files=@(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $null=Resolve-STSelectionPath $_.FullName
        [ordered]@{Path=[IO.Path]::GetRelativePath($root,$_.FullName).Replace('\','/');Length=$_.Length;Sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
    })
    $directories=@(Get-ChildItem -LiteralPath $root -Directory -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $null=Resolve-STSelectionPath -Path $_.FullName -Directory
        [IO.Path]::GetRelativePath($root,$_.FullName).Replace('\','/')
    })
    [ordered]@{Manifest=$manifest;Root=$root;Guid=[string]$data.GUID;Version=[string]$data.ModuleVersion;Files=$files;Directories=$directories}
}
if (-not [IO.Path]::IsPathFullyQualified($OutputPath) -or (Test-Path -LiteralPath $OutputPath)) { throw 'ST_PACKET_OUTPUT: requires new absolute file.' }
$packet=[ordered]@{Schema='ST.Foundation.Selection/1';Foundation=Get-ModulePacket $FoundationManifest;SignalGraph=Get-ModulePacket $SignalGraphManifest}
if ($IncludeAdapterEntryPoints) {
    $packet.EntryPoints=@(Get-Content "$PSScriptRoot/Fixtures/production-loaders.json" -Raw|ConvertFrom-Json|ForEach-Object {
        $entry=Get-ModulePacket ([IO.Path]::GetFullPath((Join-Path "$PSScriptRoot/Fixtures" $_.Manifest)))
        $guard=Resolve-STSelectionPath ([IO.Path]::GetFullPath((Join-Path $entry.Root '../../../Bootstrap/Initialize-STFoundation.ps1')))
        $entry.Guard=[ordered]@{Path=$guard;Sha256=(Get-FileHash -LiteralPath $guard).Hash}
        $entry
    })
}
$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($packet | ConvertTo-Json -Depth 15))
$stream=[IO.File]::Open($OutputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
$sha=(Get-FileHash -LiteralPath $OutputPath).Hash
$null=Read-STSelectionPacket -Path $OutputPath -Sha256 $sha
[pscustomobject]@{Path=$OutputPath;Sha256=$sha}
