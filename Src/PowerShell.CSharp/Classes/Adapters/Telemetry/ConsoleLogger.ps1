
<#
Class: ConsoleLogger
Purpose: Write log messages to the console.
ActivityScope: None
Activities: None; this logger has no activity-bearing Invoke method.
#>
class ConsoleLogger {
    [void] Log([string]$level, [string]$message, [string]$exception = $null) {
        $timestamp = (Get-Date).ToString('u')
        if ($exception) {
            Write-Host "[$timestamp] $($level): $message (Exception: $exception)"
        } else {
            Write-Host "[$timestamp] $($level): $message"
        }
    }
}
