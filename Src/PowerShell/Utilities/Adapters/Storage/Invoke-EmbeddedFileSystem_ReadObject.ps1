function Invoke-EmbeddedFileSystem_ReadObject {
    param (
        [Signal]$Signal,
        [Parameter(Mandatory)][string]$VirtualPath,
        [Parameter()][string]$PathSuffix,
        [Parameter()][AllowNull()][string]$TargetPath,
        [switch]$TargetPathProvided,
        [string]$SignalLevel = "Critical",
        [Parameter()][object]$Addresses
    )

    $opSignal = [Signal]::Start("Invoke-ReadVirtualFileFromAddresses:$VirtualPath", $Signal) | Select-Object -Last 1

    try {
        if ($TargetPathProvided) {
            if ([string]::IsNullOrWhiteSpace($TargetPath) -or -not [System.IO.Path]::IsPathFullyQualified($TargetPath) -or $TargetPath -match '^[^:]+::') {
                return $opSignal.LogCritical('Config.TargetPath must be a nonempty absolute filesystem path.')
            }
            $TargetPath = [System.IO.Path]::GetFullPath($TargetPath)
        }
        # ░▒▓█ NORMALIZE FILE EXTENSION █▓▒░
        if ($PathSuffix -and -not $VirtualPath.ToLower().EndsWith($PathSuffix)) {
            $VirtualPath = "$VirtualPath$PathSuffix"
        }

        foreach ($address in $Addresses) {
            $fullPath = Join-Path -Path $address -ChildPath $VirtualPath

            if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
                if ($TargetPathProvided) {
                    $sourcePath = [System.IO.Path]::GetFullPath($fullPath)
                    if ([string]::Equals($sourcePath, $TargetPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                        return $opSignal.LogCritical('Source and Config.TargetPath must differ.')
                    }
                    $parent = [System.IO.Path]::GetDirectoryName($TargetPath)
                    $tempPath = $null
                    try {
                        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
                        $tempPath = [System.IO.Path]::Combine($parent, '.st-read-' + [guid]::NewGuid().ToString('N') + '.tmp')
                        [System.IO.File]::Copy($sourcePath, $tempPath, $false)
                        [System.IO.File]::Move($tempPath, $TargetPath, $true)
                        $opSignal.SetResult($TargetPath)
                        return $opSignal
                    }
                    finally {
                        if ($tempPath -and [System.IO.File]::Exists($tempPath)) { [System.IO.File]::Delete($tempPath) }
                    }
                }
                $content = Get-Content -Path $fullPath -Raw
                $opSignal.SetResult($content)
                $logVirtualPath = $VirtualPath.Replace('\', '/')
                $opSignal.LogInformation("📄 Found and read file: '$logVirtualPath'")
                return $opSignal
            }
        }

        if ($TargetPathProvided) {
            return $opSignal.LogCritical("File '$VirtualPath' not found in any address.")
        }
        $opSignal.LogMessage($SignalLevel, "File '$VirtualPath' not found in any address.")
    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Invoke-ReadVirtualFileFromAddresses: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}
