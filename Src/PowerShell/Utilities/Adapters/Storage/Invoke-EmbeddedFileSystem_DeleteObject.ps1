function Invoke-EmbeddedFileSystem_DeleteObject {
    param (
        [Parameter(Mandatory)][Signal]$Signal,
        [Parameter(Mandatory)][string]$VirtualPath,
        [Parameter()][string]$PathSuffix,
        [Parameter(Mandatory)][object]$Addresses
    )

    $opSignal = [Signal]::Start("Invoke-EmbeddedFileSystem_DeleteObject:$VirtualPath", $Signal) | Select-Object -Last 1

    try {
        # ░▒▓█ NORMALIZE FILE EXTENSION █▓▒░
        if ($PathSuffix -and -not $VirtualPath.ToLower().EndsWith($PathSuffix.ToLower())) {
            $VirtualPath = "$VirtualPath$PathSuffix"
        }

        $address = @($Addresses)[0]
        if ($null -eq $address) {
            return $opSignal.LogCritical("No addresses provided to delete file '$VirtualPath'.")
        }

        $fullPath = Join-Path -Path $address -ChildPath $VirtualPath
        $logVirtualPath = $VirtualPath.Replace('\', '/')

        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            $opSignal.LogInformation("🗑️ File already absent: '$logVirtualPath' -> '$fullPath'")
            $opSignal.SetResult($false)
            return $opSignal
        }

        [System.IO.File]::Delete($fullPath)

        $opSignal.LogInformation("🗑️ Deleted file: '$logVirtualPath' -> '$fullPath'")
        $opSignal.SetResult($true)
    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Invoke-EmbeddedFileSystem_DeleteObject: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}
