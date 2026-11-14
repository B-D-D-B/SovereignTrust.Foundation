
<#
Class: TelemetryLogger
Purpose: Write telemetry log messages to the console.
ActivityScope: None
Activities: None; this logger has no activity-bearing Invoke method.
#>
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
