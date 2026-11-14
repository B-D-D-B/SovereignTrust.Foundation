function Wait-ForFileUnlock {
    param (
        [string]$FilePath,
        [int]$TimeoutSeconds = 10
    )

    $signal = [Signal]::Start("Wait-ForFileUnlock") | Select-Object -Last 1

    if (-not (Test-Path $FilePath)) {
        $signal.LogCritical("❌ File not found: $FilePath")
        return $signal
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            $stream = [System.IO.File]::Open($FilePath, 'Open', 'ReadWrite', 'None')
            if ($stream) {
                $stream.Close()
                $signal.SetResult($true)
                $signal.LogInformation("✅ File unlocked: $FilePath")
                return $signal
            }
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }

    $signal.SetResult($false)
    $signal.LogWarning("Timeout reached. File is still locked: $FilePath")
    return $signal
}
