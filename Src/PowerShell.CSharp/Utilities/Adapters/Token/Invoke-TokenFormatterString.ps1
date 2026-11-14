function Invoke-TokenFormatterString {
    param (
        [Parameter(Mandatory)][string]$Path,
        [object]$Plan
    )

    $opSignal = [Signal]::Start("Invoke-TokenFormatterString") | Select-Object -Last 1

    try {
        # everything after the 2nd '.'
        $parts = $Path -split '\.', 3
        $formatted = if ($parts.Count -ge 3) { $parts[2] } else { '' }

        $result = $formatted | ConvertTo-Json -Depth 100 
        $opSignal.SetResult($result)

        $opSignal.LogInformation("✅ String Created from Path")
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Invoke-TokenFormatterString: $_", $null, $_)
    }

    return $opSignal
}
