function Invoke-TokenFormatterVirtualFolder {
    param (
        [Parameter(Mandatory)][string]$Path,
        [object]$Plan
    )

    $opSignal = [Signal]::Start("Invoke-TokenFormatterVirtualFolder") | Select-Object -Last 1

    try {
        # Split into path segments
        $segments = $Path -split '\.'
        $formatted = ($segments[2..($segments.Count - 1)] -join '/') + "/"

         $opSignal.SetResult($formatted)

        $opSignal.LogInformation("✅ Formatted path: $formatted")
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Invoke-TokenFormatterVirtualFolder: $_", $null, $_)
    }

    return $opSignal
}
