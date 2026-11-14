if ([Environment]::GetEnvironmentVariables('Process').Contains('ST_FOUNDATION_MANIFEST')) {
    . "$PSScriptRoot/STFoundationSelection.ps1"
    $currentManifest=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../SovereignTrust.Foundation.psd1'))
    $selection=Get-STFoundationSelection -LegacyManifest $currentManifest
    if ($selection.Foundation.Manifest -ne $currentManifest) { throw 'ST_SELECTION_MISMATCH: imported Foundation differs from selected manifest.' }
    Initialize-STSelectedProcessDiscovery -Selection $selection
    Initialize-STSelectedDependency -Selection $selection
} else {
    Import-Module -Name SignalGraph -ErrorAction Stop
}
