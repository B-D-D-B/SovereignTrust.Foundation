function Read-HydrationFile {
    param (
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][string]$Format = "json"
    )
    $signal = [Signal]::Start("Read-HydrationFile:$Path") | Select-Object -Last 1
    try {
        if (-not (Test-Path $Path)) {
            return $signal.LogCritical("❌ File not found: $Path")
        }
        $raw = Get-Content -Path $Path -Raw
        switch ($Format.ToLower()) { 
            "json" {
                $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
                $signal.SetResult($parsed)
            }
            "xml" {
                $parsed = [xml]$raw
                $signal.SetResult($parsed)
            }
            "txt" {
                $signal.SetResult(@{ Raw = $raw; Lines = $raw -split "`r?`n"; Text = $raw })
            }
            "text" {
                $signal.SetResult(@{ Raw = $raw; Lines = $raw -split "`r?`n"; Text = $raw })
            }
            "md" {
                $signal.SetResult(@{ Raw = $raw; Lines = $raw -split "`r?`n"; Text = $raw })
            }
            default {
                return $signal.LogCritical("❌ Unsupported hydration format: $Format")
            }
        }
        $signal.LogInformation("✅ File parsed as $Format.")
    }
    catch {
        $signal.LogCritical("🔥 Failed to parse $($Format): $($_.Exception.Message)")
    }
    return $signal
}