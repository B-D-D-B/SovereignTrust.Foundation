function Read-JsonFileAsSignal {
    [CmdletBinding()]
    param (
        [string]$Path,
        [string]$RootPath
    )

    if ($null -ne $RootPath)
    {
        $Path = Join-Path -Path $RootPath -ChildPath $Path
    }

    $opSignal = [Signal]::Start("Read-JsonFileAsSignal") | Select-Object -Last 1
    $opSignal.LogVerbose("📖 Reading JSON file from: $Path")

    if (-not (Test-Path -Path $Path)) {
        $opSignal.LogCritical("❌ File does not exist at path: $Path")
        return $opSignal
    }

    try {
        $rawContent = Get-Content -Raw -Path $Path
        $json = $rawContent | ConvertFrom-Json -Depth 20
        $opSignal.SetResult($json)
        $opSignal.LogInformation("✅ JSON successfully parsed from: $Path")
    }
    catch {
        $opSignal.LogCritical("💥 Failed to parse JSON at path: $($Path): $_")
    }

    return $opSignal
}
