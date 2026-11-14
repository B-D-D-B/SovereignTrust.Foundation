[CmdletBinding()]
param([Parameter(Mandatory)][string]$SelectionPacket,[Parameter(Mandatory)][string]$SelectionPacketSha256,
      [Parameter(Mandatory)][string]$RunRoot)
$ErrorActionPreference='Stop'
if(Test-Path $RunRoot){throw 'Requires new RunRoot'}
$null=[IO.Directory]::CreateDirectory($RunRoot)
$packet=Get-Content $SelectionPacket -Raw|ConvertFrom-Json -Depth 30
$launcher=Join-Path $PSScriptRoot 'st-test-csharp.ps1'
function Invoke-EntryCase($Name,$Packet,$Sha,$Entry,$Expected) {
    $text=& (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $launcher -SelectionPacket $Packet -SelectionPacketSha256 $Sha -Mode LoaderCheck -EntryPoint $Entry -RunRoot (Join-Path $RunRoot $Name) 2>&1
    $code=$LASTEXITCODE
    $pass=if($Expected){$code -ne 0 -and ($text|Out-String)-match $Expected}else{$code -eq 0}
    [IO.File]::WriteAllText((Join-Path $RunRoot ($Name+'.output.txt')),($text|Out-String))
    [ordered]@{Case=$Name;Pass=$pass;ExitCode=$code;Expected=$Expected;Observed=if($Expected){$text|Out-String}else{$null}}
}
$results=@()
$entry=$packet.EntryPoints[0]
$results+=Invoke-EntryCase ReviewedOriginal $SelectionPacket $SelectionPacketSha256 $entry.Manifest $null
$unknown=Join-Path $RunRoot 'Unknown.psd1'
$sentinel=Join-Path $RunRoot 'unreviewed-effect.txt'
[IO.File]::WriteAllText($unknown,"@{RootModule='Unknown.psm1';ModuleVersion='1.0';ScriptsToProcess=@('../../../Bootstrap/Initialize-STFoundation.ps1')}")
[IO.File]::WriteAllText((Join-Path $RunRoot 'Unknown.psm1'),("[IO.File]::WriteAllText('"+$sentinel.Replace("'","''")+"','unexpected')"))
$results+=Invoke-EntryCase UnknownMarker $SelectionPacket $SelectionPacketSha256 $unknown 'ST_ENTRYPOINT_MEMBERSHIP'
# A run-owned clone supplies a byte-bound reviewed preimage, then changes only
# its manifest after approval. Original production sources are never mutated.
$clone=Join-Path $RunRoot 'ModifiedAdapter';Copy-Item -LiteralPath $entry.Root -Destination $clone -Recurse
$modified=$packet|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30
$cloneEntry=$modified.EntryPoints[0]
$cloneEntry.Root=$clone;$cloneEntry.Manifest=Join-Path $clone ([IO.Path]::GetFileName($entry.Manifest))
$reviewed=Join-Path $RunRoot 'clone-reviewed.json'
[IO.File]::WriteAllText($reviewed,($modified|ConvertTo-Json -Depth 30))
$sha=(Get-FileHash $reviewed).Hash
$manifest=Get-Content $cloneEntry.Manifest -Raw
$manifest=$manifest.Replace("ScriptsToProcess = @('../../../Bootstrap/Initialize-STFoundation.ps1')","ScriptsToProcess = @('../../../Bootstrap/Initialize-STFoundation.ps1','Unexpected.ps1')")
[IO.File]::WriteAllText($cloneEntry.Manifest,$manifest)
[IO.File]::WriteAllText((Join-Path $clone 'Unexpected.ps1'),("[IO.File]::WriteAllText('"+$sentinel.Replace("'","''")+"','unexpected')"))
$results+=Invoke-EntryCase ModifiedReviewed $reviewed $sha $cloneEntry.Manifest 'ST_ENTRYPOINT_IDENTITY'
$effects=[int](Test-Path $sentinel)
if($effects){$results+=[ordered]@{Case='ZeroUnreviewedEffects';Pass=$false}}
$pass=@($results|Where-Object Pass).Count
$summary=[ordered]@{Pass=$pass;Fail=$results.Count-$pass;Total=$results.Count;UnreviewedFixtureEffects=$effects;Results=$results}
[IO.File]::WriteAllText((Join-Path $RunRoot 'summary.json'),($summary|ConvertTo-Json -Depth 10))
$summary|ConvertTo-Json -Depth 10
if($summary.Fail){exit 1}
