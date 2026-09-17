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

    function New-RunspaceFailureResult {
        param(
            [int]$Index,
            [string]$ErrorMessage
        )

        return [PSCustomObject]@{
            Index                = $Index
            InitializationSignal = $null
            InitializationFailed = $true
            WorkerSignal         = $null
            WorkerFailed         = $true
            Error                = $ErrorMessage
        }
    }

    function ConvertFrom-RunspaceResult {
        param(
            [object]$Result,
            [int]$ExpectedIndex
        )

        if ($null -eq $Result) {
            throw "Runspace work item $ExpectedIndex returned a null result record."
        }

        $requiredProperties = @(
            'Index',
            'InitializationSignal',
            'InitializationFailed',
            'WorkerSignal',
            'WorkerFailed',
            'Error'
        )
        foreach ($propertyName in $requiredProperties) {
            if ($Result.PSObject.Properties.Name -notcontains $propertyName) {
                throw "Runspace work item $ExpectedIndex returned a result record without '$propertyName'."
            }
        }

        if ([int]$Result.Index -ne $ExpectedIndex) {
            throw "Runspace work item $ExpectedIndex returned result index '$($Result.Index)'."
        }

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
        Write-Verbose "Runspace module: $FoundationModulePath"
        if (-not (Test-Path -LiteralPath $FoundationModulePath -PathType Leaf)) {
            $null = $opSignal.LogCritical("Runspace module was not found: $FoundationModulePath")
            return $opSignal
        }

        $workItemIndexes = @($WorkItems | ForEach-Object { [int]$_.Index })
        if (@($workItemIndexes | Select-Object -Unique).Count -ne $workItemIndexes.Count) {
            $null = $opSignal.LogCritical('Runspace work item indexes must be unique.')
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

            function Test-IsRunspaceSignal {
                param([object]$InputObject)

                if ($null -eq $InputObject) {
                    return $false
                }

                $methodNames = @($InputObject.PSObject.Methods.Name)
                return $methodNames -contains 'Failure' -and
                    $methodNames -contains 'HasResult' -and
                    $methodNames -contains 'GetResult'
            }

            $initializationSignal = $null
            $workerSignal = $null

            try {
                $environment = ConvertFrom-Json -InputObject $EnvironmentJson -Depth 100 -ErrorAction Stop
                $initializationSignal = Initialize-STEnvironment -Environment $environment | Select-Object -Last 1

                if (-not (Test-IsRunspaceSignal -InputObject $initializationSignal)) {
                    throw 'Initialize-STEnvironment did not return a Signal.'
                }

                if (-not $initializationSignal.Failure() -and $initializationSignal.HasResult()) {
                    $runtime = $initializationSignal.GetResult()
                    $workerSignal = & $WorkerCommand `
                        -Runtime $runtime `
                        -WorkItem $WorkItem `
                        -Context $WorkerContext `
                    | Select-Object -Last 1

                    if (-not (Test-IsRunspaceSignal -InputObject $workerSignal)) {
                        throw "Worker command '$WorkerCommand' did not return a Signal."
                    }
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
            catch {
                $initializationIsSignal = Test-IsRunspaceSignal -InputObject $initializationSignal
                $workerIsSignal = Test-IsRunspaceSignal -InputObject $workerSignal
                $initializationRecord = if ($initializationIsSignal) {
                    ConvertTo-RunspaceSignalRecord -InputSignal $initializationSignal -IncludeResult $false
                }
                else {
                    $null
                }
                $workerRecord = if ($workerIsSignal) {
                    ConvertTo-RunspaceSignalRecord -InputSignal $workerSignal -IncludeResult $true
                }
                else {
                    $null
                }

                [PSCustomObject]@{
                    Index                = [int]$WorkItem.Index
                    InitializationSignal = $initializationRecord
                    InitializationFailed = -not $initializationIsSignal -or $initializationSignal.Failure() -or -not $initializationSignal.HasResult()
                    WorkerSignal         = $workerRecord
                    WorkerFailed         = $true
                    Error                = $_.Exception.Message
                }
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

            $inlineResult = ConvertFrom-RunspaceResult -Result $inlineOutput[-1] -ExpectedIndex $DebugWorkItemIndex
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
            $powerShell = $null
            try {
                $powerShell = [PowerShell]::Create()
                $powerShell.RunspacePool = $pool
                $null = $powerShell.AddScript($workerScript.ToString()).AddParameters(@{
                    EnvironmentJson = $environmentJson
                    WorkItem        = $workItem
                    WorkerCommand    = $WorkerCommand
                    WorkerContext    = $WorkerContext
                })

                $handle = $powerShell.BeginInvoke()
                $jobs.Add([PSCustomObject]@{
                    Index      = [int]$workItem.Index
                    PowerShell = $powerShell
                    Handle     = $handle
                })
                $powerShell = $null
            }
            finally {
                if ($null -ne $powerShell) {
                    $powerShell.Dispose()
                }
            }
        }

        foreach ($job in $jobs) {
            try {
                $jobOutput = @($job.PowerShell.EndInvoke($job.Handle))
                $jobErrors = @($job.PowerShell.Streams.Error)

                if ($jobOutput.Count -gt 0) {
                    $result = ConvertFrom-RunspaceResult -Result $jobOutput[-1] -ExpectedIndex $job.Index
                    if ($jobErrors.Count -gt 0) {
                        $result.Error = ($jobErrors | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
                    }
                    $results.Add($result)
                }
                else {
                    $errorMessage = ($jobErrors | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
                    if ([string]::IsNullOrWhiteSpace($errorMessage)) {
                        $errorMessage = "Runspace work item $($job.Index) did not return a result."
                    }
                    $results.Add((New-RunspaceFailureResult -Index $job.Index -ErrorMessage $errorMessage))
                }
            }
            catch {
                Write-Verbose "Runspace pool job $($job.Index) failed: $($_.Exception.Message)"
                $results.Add((New-RunspaceFailureResult -Index $job.Index -ErrorMessage $_.Exception.Message))
            }
            finally {
                $job.PowerShell.Dispose()
                $job.PowerShell = $null
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
