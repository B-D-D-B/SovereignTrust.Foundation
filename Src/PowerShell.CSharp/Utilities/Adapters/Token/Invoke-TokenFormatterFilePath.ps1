function Invoke-TokenFormatterFilePath {
    param (
        [Parameter(Mandatory)][string]$Path,
        [object]$Plan
    )

    $opSignal = [Signal]::Start("Invoke-TokenFormatterFilePath") | Select-Object -Last 1

    try {
        # Split into path segments
        $segments = $Path -split '\.'

        if ($segments.Count -lt 3) {
            $opSignal.LogWarning("Not enough path segments to format: $Path")
            return $opSignal
        }

        # Always skip first two: Formatter.Type
        $fileSegments = $segments[2..($segments.Count - 1)]
        $rawPath = ($fileSegments -join '.')

        # Early exit if already formatted
        if ($rawPath -match '[\\/]+') {
            $opSignal.SetResult($rawPath)
            $opSignal.LogInformation("📁 File path already formatted: $rawPath")
            return $opSignal
        }

        # Determine platform separator
        $sep = [System.IO.Path]::DirectorySeparatorChar

        $root = $fileSegments[0]
        $remainder = $fileSegments[1..($fileSegments.Count - 1)] -join $sep

        if ($root.Length -eq 1) {
            # C:\ style
            $formatted = "${root}:${sep}${remainder}"
        }
        else {
            # \\UNC\Path style
            $formatted = "${sep}${sep}${root}${sep}${remainder}"
        }

        $opSignal.SetResult($formatted)
        $opSignal.LogInformation("✅ Formatted path: $formatted")
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Invoke-TokenFormatterFilePath: $_", $null, $_)
    }

    return $opSignal
}
