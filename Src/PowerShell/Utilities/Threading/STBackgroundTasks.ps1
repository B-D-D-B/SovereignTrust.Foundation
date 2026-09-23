if ($null -eq (Get-Variable -Name STBackgroundTasks -Scope Script -ErrorAction SilentlyContinue)) {
    $script:STBackgroundTasks = [hashtable]::Synchronized(@{})
}

function ConvertTo-STBackgroundTaskStatus {
    param([Parameter(Mandatory)][object]$Task)

    [PSCustomObject]@{
        TaskId       = [string]$Task.TaskId
        TaskName     = [string]$Task.TaskName
        OwnerId      = [string]$Task.OwnerId
        State        = [string]$Task.State
        CreatedUtc   = $Task.CreatedUtc
        StartedUtc   = $Task.StartedUtc
        CompletedUtc = $Task.CompletedUtc
    }
}

function ConvertFrom-STSignalRecord {
    [CmdletBinding()]
    param([AllowNull()][object]$Record)

    if ($null -eq $Record) { return $null }

    $signal = [Signal]::Start([string]$Record.Name) | Select-Object -Last 1
    if ($null -ne $Record.Meta) { $signal.SetMeta($Record.Meta) }
    foreach ($entry in @($Record.Entries)) {
        $null = $signal.LogMessage([string]$entry.Level, [string]$entry.Message, @($entry.Tags))
    }
    if ([bool]$Record.HasResult) { $signal.SetResult($Record.Result) }
    return $signal
}

function Start-STBackgroundTaskExecution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Task,
        [switch]$Inline
    )

    $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $initialSessionState.ImportPSModule(@([string]$Task.FoundationModulePath))
    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace(
        $Host,
        $initialSessionState
    )
    $runspace.ApartmentState = [System.Threading.ApartmentState]::MTA
    $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $runspace.Open()

    $workerScript = {
        param(
            [string]$EnvironmentJson,
            [string]$WorkItemJson,
            [string]$WorkerContextJson,
            [string]$WorkerCommand,
            [string]$TaskId
        )

        function ConvertTo-WorkerSignalRecord {
            param([object]$InputSignal, [bool]$IncludeResult)
            if ($null -eq $InputSignal) { return $null }

            $entries = foreach ($entry in @($InputSignal.Entries)) {
                [PSCustomObject]@{
                    Level   = [string]$entry.Level
                    Message = [string]$entry.Message
                    Tags    = @($entry.Tags)
                }
            }

            [PSCustomObject]@{
                Name      = [string]$InputSignal.Name
                Meta      = $InputSignal.Meta
                Entries   = @($entries)
                HasResult = $IncludeResult -and $null -ne $InputSignal.Result
                Result    = if ($IncludeResult) { $InputSignal.Result } else { $null }
            }
        }

        function Test-WorkerSignal {
            param([object]$InputObject)
            if ($null -eq $InputObject) { return $false }
            $methods = @($InputObject.PSObject.Methods.Name)
            return $methods -contains 'Failure' -and $methods -contains 'HasResult'
        }

        $initializationSignal = $null
        $workerSignal = $null
        try {
            $environment = ConvertFrom-Json -InputObject $EnvironmentJson -Depth 100 -ErrorAction Stop
            $workItem = ConvertFrom-Json -InputObject $WorkItemJson -Depth 100 -ErrorAction Stop
            $workerContext = ConvertFrom-Json -InputObject $WorkerContextJson -Depth 100 -ErrorAction Stop
            $initializationSignal = Initialize-STEnvironment -Environment $environment | Select-Object -Last 1
            if (-not (Test-WorkerSignal $initializationSignal)) {
                throw 'Initialize-STEnvironment did not return a Signal.'
            }
            if ($initializationSignal.Failure() -or -not $initializationSignal.HasResult()) {
                throw 'Background runtime initialization failed.'
            }

            $workerSignal = & $WorkerCommand `
                -Runtime $initializationSignal.GetResult() `
                -WorkItem $workItem `
                -Context $workerContext |
                Select-Object -Last 1
            if (-not (Test-WorkerSignal $workerSignal)) {
                throw "Worker command '$WorkerCommand' did not return a Signal."
            }

            [PSCustomObject]@{
                TaskId               = $TaskId
                InitializationSignal = ConvertTo-WorkerSignalRecord $initializationSignal $false
                WorkerSignal         = ConvertTo-WorkerSignalRecord $workerSignal $true
                Failed               = $initializationSignal.Failure() -or $workerSignal.Failure()
                Error                = $null
            }
        }
        catch {
            [PSCustomObject]@{
                TaskId               = $TaskId
                InitializationSignal = if (Test-WorkerSignal $initializationSignal) { ConvertTo-WorkerSignalRecord $initializationSignal $false } else { $null }
                WorkerSignal         = if (Test-WorkerSignal $workerSignal) { ConvertTo-WorkerSignalRecord $workerSignal $true } else { $null }
                Failed               = $true
                Error                = (@(
                    ($_.Exception.Message),
                    ($_.ScriptStackTrace)
                ) | Where-Object { $_ }) -join [Environment]::NewLine
            }
        }
    }

    if ($Inline) {
        try {
            $Task.StartedUtc = [DateTime]::UtcNow
            $output = @(& $workerScript `
                -EnvironmentJson $Task.EnvironmentJson `
                -WorkItemJson $Task.WorkItemJson `
                -WorkerContextJson $Task.WorkerContextJson `
                -WorkerCommand $Task.WorkerCommand `
                -TaskId $Task.TaskId)
            $Task.CompletionEnvelope = if ($output.Count -gt 0) { $output[-1] } else { $null }
            $Task.State = if ($null -eq $Task.CompletionEnvelope -or [bool]$Task.CompletionEnvelope.Failed) { 'Failed' } else { 'Completed' }
            $Task.Error = if ($null -ne $Task.CompletionEnvelope) { $Task.CompletionEnvelope.Error } else { 'Inline worker returned no completion envelope.' }
            $Task.CompletedUtc = [DateTime]::UtcNow
            return
        }
        finally {
            try { $runspace.Close() } catch { }
            $runspace.Dispose()
        }
    }

    $powerShell = [System.Management.Automation.PowerShell]::Create()
    try {
        $powerShell.Runspace = $runspace
        $null = $powerShell.AddScript($workerScript.ToString()).AddParameters(@{
            EnvironmentJson  = $Task.EnvironmentJson
            WorkItemJson     = $Task.WorkItemJson
            WorkerContextJson = $Task.WorkerContextJson
            WorkerCommand    = $Task.WorkerCommand
            TaskId           = $Task.TaskId
        })
        $Task.PowerShell = $powerShell
        $Task.Runspace = $runspace
        $Task.StartedUtc = [DateTime]::UtcNow
        $Task.State = 'Running'
        $Task.Handle = $powerShell.BeginInvoke()
        $powerShell = $null
        $runspace = $null
    }
    finally {
        if ($null -ne $powerShell) { $powerShell.Dispose() }
        if ($null -ne $runspace) {
            try { $runspace.Close() } catch { }
            $runspace.Dispose()
        }
    }
}

function Update-STBackgroundTasks {
    [CmdletBinding()]
    param([Signal]$Signal)

    $opSignal = [Signal]::Start('Update-STBackgroundTasks', $Signal) | Select-Object -Last 1
    try {
        foreach ($task in @($script:STBackgroundTasks.Values)) {
            if ($task.State -ne 'Running' -or $null -eq $task.Handle -or -not $task.Handle.IsCompleted) { continue }
            try {
                $output = @($task.PowerShell.EndInvoke($task.Handle))
                $streamErrors = @($task.PowerShell.Streams.Error)
                $task.CompletionEnvelope = if ($output.Count -gt 0) { $output[-1] } else { $null }
                if ($null -eq $task.CompletionEnvelope) {
                    $task.Error = 'Background task returned no completion envelope.'
                    $task.State = 'Failed'
                }
                elseif ([bool]$task.CompletionEnvelope.Failed -or $streamErrors.Count -gt 0) {
                    $task.Error = (@($task.CompletionEnvelope.Error) + @($streamErrors | ForEach-Object { ($_ | Out-String).Trim() }) | Where-Object { $_ }) -join [Environment]::NewLine
                    $task.State = 'Failed'
                }
                else {
                    $task.State = 'Completed'
                }
            }
            catch {
                $task.Error = $_.Exception.ToString()
                $task.State = 'Failed'
            }
            finally {
                $task.CompletedUtc = [DateTime]::UtcNow
                if ($null -ne $task.PowerShell) { $task.PowerShell.Dispose(); $task.PowerShell = $null }
                if ($null -ne $task.Runspace) {
                    try { $task.Runspace.Close() } catch { }
                    $task.Runspace.Dispose()
                    $task.Runspace = $null
                }
                $task.Handle = $null
            }
        }

        $runningCount = @($script:STBackgroundTasks.Values | Where-Object State -eq 'Running').Count
        foreach ($queuedTask in @($script:STBackgroundTasks.Values | Where-Object State -eq 'Queued' | Sort-Object CreatedUtc)) {
            if ($runningCount -ge [int]$queuedTask.MaxConcurrent) { continue }
            try {
                Start-STBackgroundTaskExecution -Task $queuedTask
                $runningCount++
            }
            catch {
                $queuedTask.State = 'Failed'
                $queuedTask.Error = $_.Exception.ToString()
                $queuedTask.CompletedUtc = [DateTime]::UtcNow
            }
        }

        $opSignal.SetResult(@($script:STBackgroundTasks.Values | ForEach-Object { ConvertTo-STBackgroundTaskStatus $_ }))
    }
    catch {
        $null = $opSignal.LogCritical("Failed to update background tasks: $($_.Exception.Message)", $null, $_)
    }
    return $opSignal
}

function Start-STBackgroundTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Signal]$Signal,
        [Parameter(Mandatory)][object]$EnvironmentDefinition,
        [Parameter(Mandatory)][object]$WorkItem,
        [Parameter(Mandatory)][object]$WorkerContext,
        [Parameter(Mandatory)][string]$WorkerCommand,
        [string]$TaskName = 'BackgroundTask',
        [string]$OwnerId = 'Default',
        [ValidateRange(1, 1024)][int]$MaxConcurrent = 4,
        [string]$FoundationModulePath,
        [switch]$DebugInline
    )

    $opSignal = [Signal]::Start('Start-STBackgroundTask', $Signal) | Select-Object -Last 1
    $task = $null
    try {
        if ([string]::IsNullOrWhiteSpace($FoundationModulePath)) {
            $FoundationModulePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\SovereignTrust.Foundation.psd1'))
        }
        if (-not (Test-Path -LiteralPath $FoundationModulePath -PathType Leaf)) {
            throw "Foundation module was not found: $FoundationModulePath"
        }

        $null = Update-STBackgroundTasks -Signal $opSignal | Select-Object -Last 1
        $taskId = [guid]::NewGuid().ToString()
        $task = [PSCustomObject]@{
            TaskId              = $taskId
            TaskName            = $TaskName
            OwnerId             = $OwnerId
            State               = 'Queued'
            CreatedUtc          = [DateTime]::UtcNow
            StartedUtc          = $null
            CompletedUtc        = $null
            MaxConcurrent       = $MaxConcurrent
            FoundationModulePath = $FoundationModulePath
            EnvironmentJson     = ConvertTo-Json -InputObject $EnvironmentDefinition -Depth 100 -Compress -ErrorAction Stop
            WorkItemJson        = ConvertTo-Json -InputObject $WorkItem -Depth 100 -Compress -ErrorAction Stop
            WorkerContextJson   = ConvertTo-Json -InputObject $WorkerContext -Depth 100 -Compress -ErrorAction Stop
            WorkerCommand       = $WorkerCommand
            PowerShell          = $null
            Runspace            = $null
            Handle              = $null
            CompletionEnvelope  = $null
            Error               = $null
        }
        $script:STBackgroundTasks[$taskId] = $task

        if ($DebugInline) {
            Start-STBackgroundTaskExecution -Task $task -Inline
        }
        elseif (@($script:STBackgroundTasks.Values | Where-Object State -eq 'Running').Count -lt $MaxConcurrent) {
            Start-STBackgroundTaskExecution -Task $task
        }

        $opSignal.SetResult((ConvertTo-STBackgroundTaskStatus $task))
    }
    catch {
        if ($null -ne $task) {
            $task.State = 'Failed'
            $task.Error = $_.Exception.ToString()
            $task.CompletedUtc = [DateTime]::UtcNow
        }
        $null = $opSignal.LogCritical("Failed to start background task: $($_.Exception.Message)", $null, $_)
    }
    return $opSignal
}

function Get-STBackgroundTask {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TaskId, [Signal]$Signal)

    $opSignal = [Signal]::Start('Get-STBackgroundTask', $Signal) | Select-Object -Last 1
    $null = Update-STBackgroundTasks -Signal $opSignal | Select-Object -Last 1
    if (-not $script:STBackgroundTasks.ContainsKey($TaskId)) {
        $null = $opSignal.LogCritical("Background task '$TaskId' was not found.")
        return $opSignal
    }
    $opSignal.SetResult((ConvertTo-STBackgroundTaskStatus $script:STBackgroundTasks[$TaskId]))
    return $opSignal
}

function Receive-STBackgroundTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Signal]$Signal,
        [switch]$Wait,
        [switch]$RemoveAfterReceive
    )

    $opSignal = [Signal]::Start('Receive-STBackgroundTask', $Signal) | Select-Object -Last 1
    if (-not $script:STBackgroundTasks.ContainsKey($TaskId)) {
        $null = $opSignal.LogCritical("Background task '$TaskId' was not found.")
        return $opSignal
    }

    do {
        $updateSignal = Update-STBackgroundTasks -Signal $opSignal | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($updateSignal)) { return $opSignal }
        $task = $script:STBackgroundTasks[$TaskId]
        if ($task.State -notin @('Queued', 'Running') -or -not $Wait) { break }
        Start-Sleep -Milliseconds 100
    } while ($true)

    if ($task.State -in @('Queued', 'Running')) {
        $opSignal.SetResult([PSCustomObject]@{ Status = ConvertTo-STBackgroundTaskStatus $task; CompletionEnvelope = $null })
        return $opSignal
    }

    $result = [PSCustomObject]@{
        Status             = ConvertTo-STBackgroundTaskStatus $task
        CompletionEnvelope = $task.CompletionEnvelope
        Error              = $task.Error
    }
    $opSignal.SetResult($result)
    if ($task.State -in @('Failed', 'Cancelled')) {
        $null = $opSignal.LogCritical("Background task '$TaskId' finished with state '$($task.State)'. $($task.Error)")
    }
    if ($RemoveAfterReceive) { $script:STBackgroundTasks.Remove($TaskId) }
    return $opSignal
}

function Wait-STBackgroundTasks {
    [CmdletBinding()]
    param(
        [string]$OwnerId,
        [Signal]$Signal,
        [switch]$RemoveAfterReceive,
        [switch]$MergeWorkerSignals
    )

    $opSignal = [Signal]::Start('Wait-STBackgroundTasks', $Signal) | Select-Object -Last 1
    $ids = @($script:STBackgroundTasks.Values | Where-Object { [string]::IsNullOrWhiteSpace($OwnerId) -or $_.OwnerId -eq $OwnerId } | ForEach-Object TaskId)
    $results = foreach ($id in $ids) {
        $receiveSignal = Receive-STBackgroundTask -TaskId $id -Signal $opSignal -Wait -RemoveAfterReceive:$RemoveAfterReceive | Select-Object -Last 1
        $null = $opSignal.MergeSignal($receiveSignal)
        if ($receiveSignal.HasResult()) {
            $received = $receiveSignal.GetResult()
            if ($MergeWorkerSignals -and $null -ne $received.CompletionEnvelope) {
                $initializationSignal = ConvertFrom-STSignalRecord $received.CompletionEnvelope.InitializationSignal
                $workerSignal = ConvertFrom-STSignalRecord $received.CompletionEnvelope.WorkerSignal
                if ($null -ne $initializationSignal) { $null = $opSignal.MergeSignal($initializationSignal) }
                if ($null -ne $workerSignal) { $null = $opSignal.MergeSignal($workerSignal) }
                if (-not [string]::IsNullOrWhiteSpace([string]$received.CompletionEnvelope.Error)) {
                    $null = $opSignal.LogCritical([string]$received.CompletionEnvelope.Error)
                }
            }
            $received
        }
    }
    $opSignal.SetResult(@($results))
    return $opSignal
}

function Stop-STBackgroundTask {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TaskId, [Signal]$Signal)

    $opSignal = [Signal]::Start('Stop-STBackgroundTask', $Signal) | Select-Object -Last 1
    if (-not $script:STBackgroundTasks.ContainsKey($TaskId)) {
        $null = $opSignal.LogCritical("Background task '$TaskId' was not found.")
        return $opSignal
    }
    $task = $script:STBackgroundTasks[$TaskId]
    if ($task.State -eq 'Running' -and $null -ne $task.PowerShell) {
        try { $task.PowerShell.Stop() } catch { }
        $task.PowerShell.Dispose()
        if ($null -ne $task.Runspace) { try { $task.Runspace.Close() } catch { }; $task.Runspace.Dispose() }
    }
    $task.PowerShell = $null
    $task.Runspace = $null
    $task.Handle = $null
    $task.State = 'Cancelled'
    $task.CompletedUtc = [DateTime]::UtcNow
    $opSignal.SetResult((ConvertTo-STBackgroundTaskStatus $task))
    return $opSignal
}
