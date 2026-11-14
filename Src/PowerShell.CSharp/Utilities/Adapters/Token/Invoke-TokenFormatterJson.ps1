function Invoke-TokenFormatterJson {
    param (
        [Parameter(Mandatory)][string]$Path,
        [object]$Plan
    )

    $opSignal = [Signal]::Start("Invoke-TokenFormatterJson") | Select-Object -Last 1

    try {
        # everything after the 2nd '.'
        $parts = $Path -split '\.', 3
        $formatted = if ($parts.Count -ge 3) { $parts[2] } else { '' }

        $json = $formatted | ConvertFrom-Json -Depth 100 
        $opSignal.SetResult($json)

        $opSignal.LogInformation("✅ Json Created from Path")
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Invoke-TokenFormatterJson: $_", $null, $_)
    }

    return $opSignal
}
