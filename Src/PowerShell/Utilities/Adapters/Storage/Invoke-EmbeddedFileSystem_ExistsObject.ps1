function Invoke-EmbeddedFileSystem_ExistsObject {
    param (
        [Parameter(Mandatory)][Signal]$Signal,
        [Parameter(Mandatory)][string]$VirtualPath,
        [Parameter()][string]$PathSuffix,
        [Parameter(Mandatory)][object]$Addresses
    )

    $opSignal = [Signal]::Start("Invoke-EmbeddedFileSystem_ExistsObject:$VirtualPath", $Signal) | Select-Object -Last 1

    try {
        if ($PathSuffix -and -not $VirtualPath.EndsWith($PathSuffix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $VirtualPath = "$VirtualPath$PathSuffix"
        }

        $hasAddress = $false
        foreach ($address in @($Addresses)) {
            if ([string]::IsNullOrWhiteSpace([string]$address)) { continue }
            $hasAddress = $true
            $fullPath = Join-Path -Path $address -ChildPath $VirtualPath
            if (Test-Path -LiteralPath $fullPath -PathType Leaf -ErrorAction Stop) {
                $opSignal.SetResult($true)
                return $opSignal
            }
        }

        if (-not $hasAddress) {
            return $opSignal.LogCritical("No addresses provided to check file '$VirtualPath'.")
        }

        $opSignal.SetResult($false)
    }
    catch {
        $opSignal.LogCritical("Exception during Invoke-EmbeddedFileSystem_ExistsObject: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}
