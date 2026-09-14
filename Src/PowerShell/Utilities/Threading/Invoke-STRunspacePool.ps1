function Invoke-STRunspacePool {
    <#
    .SYNOPSIS
    Runs indexed SovereignTrust work items in fresh initialized runtimes.

    .DESCRIPTION
    The named worker command must be exported by the Foundation module and
    accept Runtime, WorkItem, and Context parameters. Results are collected and
    returned in input-index order; callers remain responsible for merging them.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Signal]$Signal,

        [Parameter(Mandatory)]
        [object]$EnvironmentDefinition,

        [Parameter(Mandatory)]
        [object[]]$WorkItems,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkerCommand,

        [Parameter(Mandatory)]
        [ValidateRange(1, 1024)]
        [int]$ThrottleLimit,

        [string]$FoundationModulePath,

        [object]$WorkerContext,

        [switch]$DebugInline,

        [int]$DebugWorkItemIndex = 0
    )

    $opSignal = [Signal]::Start('Invoke-STRunspacePool', $Signal) | Select-Object -Last 1
    $pool = $null
    $jobs = [System.Collections.Generic.List[object]]::new()
    $results = [System.Collections.Generic.List[object]]::new()

    function ConvertFrom-RunspaceSignalRecord {
        param([object]$Record)

        if ($null -eq $Record) {
            return $null
        }

        $localSignal = [Signal]::Start([string]$Record.Name) | Select-Object -Last 1
        if ($null -ne $Record.Meta) {
            $localSignal.SetMeta($Record.Meta)
        }

        foreach ($entry in @($Record.Entries)) {
            $null = $localSignal.LogMessage(
                [string]$entry.Level,
                [string]$entry.Message,
                @($entry.Tags)
            )
        }

        if ([bool]$Record.HasResult) {
            $localSignal.SetResult($Record.Result)
        }

        return $localSignal
    }

    function ConvertFrom-RunspaceResult {
        param([object]$Result)

        $Result.InitializationSignal = ConvertFrom-RunspaceSignalRecord -Record $Result.InitializationSignal
        $Result.WorkerSignal = ConvertFrom-RunspaceSignalRecord -Record $Result.WorkerSignal
        return $Result
    }

    try {
        if ([string]::IsNullOrWhiteSpace($FoundationModulePath)) {
            $FoundationModulePath = [System.IO.Path]::GetFullPath(
                (Join-Path $PSScriptRoot '..\..\SovereignTrust.Foundation.psd1')
            )
        }
        Write-Host $FoundationModulePath
        if (-not (Test-Path -LiteralPath $FoundationModulePath -PathType Leaf)) {
            $null = $opSignal.LogCritical("Runspace module was not found: $FoundationModulePath")
            return $opSignal
        }

        $environmentJson = ConvertTo-Json -InputObject $EnvironmentDefinition -Depth 100 -Compress -ErrorAction Stop
        $workerScript = {
            param(
                [string]$EnvironmentJson,
                [object]$WorkItem,
                [string]$WorkerCommand,
                [object]$WorkerContext
            )

            function ConvertTo-RunspaceSignalRecord {
                param(
                    [object]$InputSignal,
                    [bool]$IncludeResult
                )

                if ($null -eq $InputSignal) {
                    return $null
                }

                $entryRecords = foreach ($entry in @($InputSignal.Entries)) {
                    [PSCustomObject]@{
                        Level   = [string]$entry.Level
                        Message = [string]$entry.Message
                        Tags    = @($entry.Tags)
                    }
                }

                [PSCustomObject]@{
                    Name      = [string]$InputSignal.Name
                    Meta      = $InputSignal.Meta
                    Entries   = @($entryRecords)
                    HasResult = $IncludeResult -and $null -ne $InputSignal.Result
                    Result    = if ($IncludeResult) { $InputSignal.Result } else { $null }
                }
            }

            $environment = ConvertFrom-Json -InputObject $EnvironmentJson -Depth 100 -ErrorAction Stop
#            Write-Host "Initialize-STEnvironment Next"
            $initializationSignal = Initialize-STEnvironment -Environment $environment | Select-Object -Last 1
#            Write-Host "Initialize-STEnvironment Done"
            $workerSignal = $null

            if (-not $initializationSignal.Failure() -and $initializationSignal.HasResult()) {
                $runtime = $initializationSignal.GetResult()
                $workerSignal = & $WorkerCommand `
                    -Runtime $runtime `
                    -WorkItem $WorkItem `
                    -Context $WorkerContext `
                | Select-Object -Last 1
            }

            [PSCustomObject]@{
                Index                = [int]$WorkItem.Index
                InitializationSignal = ConvertTo-RunspaceSignalRecord -InputSignal $initializationSignal -IncludeResult $false
                InitializationFailed = $initializationSignal.Failure() -or -not $initializationSignal.HasResult()
                WorkerSignal         = ConvertTo-RunspaceSignalRecord -InputSignal $workerSignal -IncludeResult $true
                WorkerFailed         = $null -eq $workerSignal -or $workerSignal.Failure()
                Error                = $null
            }
        }

        if ($DebugInline) {
            $debugWorkItems = @($WorkItems | Where-Object { [int]$_.Index -eq $DebugWorkItemIndex })
            if ($debugWorkItems.Count -ne 1) {
                $null = $opSignal.LogCritical(
                    "Inline debug work item index $DebugWorkItemIndex was not found exactly once."
                )
                return $opSignal
            }

            $inlineOutput = @(& $workerScript `
                -EnvironmentJson $environmentJson `
                -WorkItem $debugWorkItems[0] `
                -WorkerCommand $WorkerCommand `
                -WorkerContext $WorkerContext)

            if ($inlineOutput.Count -eq 0) {
                $null = $opSignal.LogCritical(
                    "Inline debug work item $DebugWorkItemIndex did not return a result."
                )
                return $opSignal
            }

            $inlineResult = ConvertFrom-RunspaceResult -Result $inlineOutput[-1]
            $opSignal.SetResult(@($inlineResult))
            return $opSignal
        }

        $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $initialSessionState.ImportPSModule(@($FoundationModulePath))

        $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(
            1,
            $ThrottleLimit,
            $initialSessionState,
            $Host
        )
        $pool.ApartmentState = [System.Threading.ApartmentState]::MTA
        $pool.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
        $pool.Open()

        foreach ($workItem in @($WorkItems)) {
            $powerShell = [PowerShell]::Create()
            $powerShell.RunspacePool = $pool
            $null = $powerShell.AddScript($workerScript.ToString()).AddParameters(@{
                EnvironmentJson = $environmentJson
                WorkItem        = $workItem
                WorkerCommand    = $WorkerCommand
                WorkerContext    = $WorkerContext
            })

            $jobs.Add([PSCustomObject]@{
                Index      = [int]$workItem.Index
                PowerShell = $powerShell
                Handle     = $powerShell.BeginInvoke()
            })
        }

        foreach ($job in $jobs) {
            try {
                $jobOutput = @($job.PowerShell.EndInvoke($job.Handle))
                $jobErrors = @($job.PowerShell.Streams.Error)

                if ($jobOutput.Count -gt 0) {
                    $result = ConvertFrom-RunspaceResult -Result $jobOutput[-1]
                    if ($jobErrors.Count -gt 0) {
                        $result.Error = ($jobErrors | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
                    }
                    $results.Add($result)
                }
                else {
                    $results.Add([PSCustomObject]@{
                        Index                = $job.Index
                        InitializationSignal = $null
                        InitializationFailed = $true
                        WorkerSignal         = $null
                        WorkerFailed         = $true
                        Error                = ($jobErrors | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
                    })
                }
            }
            catch {
                Write-Host("Runspace pool job failed: $($_.Exception.Message)")
                $results.Add([PSCustomObject]@{
                    Index                = $job.Index
                    InitializationSignal = $null
                    InitializationFailed = $true
                    WorkerSignal         = $null
                    WorkerFailed         = $true
                    Error                = $_.Exception.Message
                })
            }
            finally {
                $job.PowerShell.Dispose()
            }
        }

        $opSignal.SetResult(@($results | Sort-Object -Property Index))
    }
    catch {
        $null = $opSignal.LogCritical("Runspace pool failed: $($_.Exception.Message)", $null, $_)
    }
    finally {
        foreach ($job in $jobs) {
            if ($null -ne $job.PowerShell) {
                try { $job.PowerShell.Dispose() } catch { }
            }
        }

        if ($null -ne $pool) {
            try { $pool.Close() } catch { }
            try { $pool.Dispose() } catch { }
        }
    }

    return $opSignal
}
