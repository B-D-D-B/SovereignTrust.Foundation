#obsolete
function Get-JsonObjectFromFile {
    param (
        [Parameter(Mandatory)][string]$RootFolder,
        [Parameter(Mandatory)][string]$VirtualPath,
        [bool]$RequireArray = $false
    )

    $signalName = "Get-JsonObjectFromFile:$VirtualPath"
    $signal = [Signal]::new($signalName)

    try {
        $fullPath = Join-Path $RootFolder $VirtualPath

        if (-not (Test-Path $fullPath)) {
            $signal.LogCritical("JSON file not found: $fullPath")
            return $signal
        }

        # ░▒▓█ FILE LOCK CHECK █▓▒░
        $waitSignal = Wait-ForFileUnlock -FilePath $fullPath | Select-Object -Last 1
        if ($signal.MergeSignalAndVerifyFailure($waitSignal)) {
            $signal.LogCritical("⛔ File is still locked and could not be read: $fullPath")
            return $signal
        }

        # ░▒▓█ JSON PARSING █▓▒░
        $rawJson = Get-Content -Path $fullPath -Raw -Encoding UTF8
        $parsedJson = $rawJson | ConvertFrom-Json -Depth 20 -ErrorAction Stop

        if ($RequireArray -and ($parsedJson -isnot [System.Collections.IEnumerable] -or $parsedJson -is [string])) {
            $signal.LogCritical("Invalid JSON: Root must be an array of objects.")
            return $signal
        }

        $signal.SetResult($parsedJson)
        $signal.LogInformation("✅ JSON loaded successfully from $fullPath.")
    }
    catch {
        $signal.LogCritical("🔥 Exception: parsing JSON file at $($fullPath): $($_.Exception.Message)", $null, $_)
    }

    return $signal
}
