
class TelemetryLogger {
    [void] Log([string]$level, [string]$message, [string]$exception = $null) {
        $timestamp = (Get-Date).ToString('u')
        if ($exception) {
            Write-Host "T:[$timestamp] $($level): $message (Exception: $exception)"
        } else {
            Write-Host "T:[$timestamp] $($level): $message"
        }
    }
}
