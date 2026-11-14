# InitialSessionState startup runs before the work script is parsed or invoked.
$ErrorActionPreference='Stop'
$global:STSelectedWorkerContext=$true
if ($env:PSModulePath -cne $STWorkerExpectedDiscovery) { throw 'ST_SELECTION_DISCOVERY: worker discovery drift before bootstrap.' }
. "$PSScriptRoot/STFoundationSelection.ps1"
$global:STWorkerSelection=Read-STSelectionPacket -Path $STWorkerPacket -Sha256 $STWorkerSha -KnownSignalAssembly $STWorkerKnownAssembly
Import-STSelectedFoundation -Selection $global:STWorkerSelection
$global:STWorkerProvenance=Get-STSelectionProvenance -Selection $global:STWorkerSelection
