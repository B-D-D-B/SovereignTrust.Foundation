function Invoke-EmbeddedFileSystem_WriteObject {
    param (
        [Parameter(Mandatory)][Signal]$Signal,
        [Parameter()][AllowNull()][object]$Content,
        [Parameter()][AllowNull()][string]$SourcePath,
        [Parameter(Mandatory)][string]$VirtualPath,
        [Parameter()][string]$PathSuffix,
        [Parameter(Mandatory)][object]$Addresses
    )

    $opSignal = [Signal]::Start("Invoke-EmbeddedFileSystem_WriteObject:$VirtualPath", $Signal) | Select-Object -Last 1

    try {
        # ░▒▓█ NORMALIZE FILE EXTENSION █▓▒░
        if ($PathSuffix -and -not $VirtualPath.ToLower().EndsWith($PathSuffix.ToLower())) {
            $VirtualPath = "$VirtualPath$PathSuffix"
        }
        $address = @($Addresses)[0]
        #        foreach ($address in $Addresses) {
        $fullPath = Join-Path -Path $address -ChildPath $VirtualPath

        if ($null -ne $Content) {
            if ($Content -is [pscustomobject] -or $Content -is [hashtable] -or $Content -is [ordered] -or $Content -is [System.Collections.IDictionary])
            {
                $Content = $Content | ConvertTo-Json -Depth 100
            }
            elseif ($Content -is [object[]])
            {
                if ($Content.Count -eq 1) {
                    $Content = , $Content | ConvertTo-Json -Depth 100
                }
                else {
                    $Content = $Content | ConvertTo-Json -Depth 100
                }
            }

            $dir = Split-Path -Path $fullPath -Parent
            if ($dir -and -not (Test-Path -Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
            }
            [System.IO.File]::WriteAllText($fullPath, [string]$Content, [System.Text.UTF8Encoding]::new($false))
        }
        elseif (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
            $resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).ProviderPath
            if (-not [System.IO.File]::Exists($resolvedSourcePath)) {
                return $opSignal.LogCritical("Source file does not exist: '$resolvedSourcePath'.")
            }
            $resolvedDestination = [System.IO.Path]::GetFullPath($fullPath)
            if ([string]::Equals($resolvedSourcePath, $resolvedDestination, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $opSignal.LogCritical("Source and destination paths must differ: '$resolvedSourcePath'.")
            }
            $sourceBytes = [System.IO.File]::ReadAllBytes($resolvedSourcePath)
            $dir = Split-Path -Path $fullPath -Parent
            if ($dir -and -not (Test-Path -Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
            }
            [System.IO.File]::WriteAllBytes($fullPath, $sourceBytes)
        }
        else {
            return $opSignal.LogCritical("Embedded file write requires Config.Content or Config.SourcePath.")
        }

        $logVirtualPath = $VirtualPath.Replace('\', '/')
        $opSignal.LogInformation("📝 Wrote file: '$logVirtualPath' -> '$fullPath'")
        $opSignal.SetResult($fullPath)
        return $opSignal
        #       }

        $opSignal.LogCritical("No addresses provided to write file '$VirtualPath'.")
    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Invoke-EmbeddedFileSystem_WriteObject: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}
