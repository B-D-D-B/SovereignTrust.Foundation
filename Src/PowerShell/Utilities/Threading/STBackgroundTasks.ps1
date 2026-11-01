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

function ConvertTo-STBackgroundStopStatus {
    param([object]$Task, [string]$PriorState, [bool]$StopRequested, [bool]$StopCompleted,
          [AllowNull()][object]$RunspaceClosed, [bool]$AlreadyTerminal)

    $status = ConvertTo-STBackgroundTaskStatus $Task
    $status | Add-Member -NotePropertyName PriorState -NotePropertyValue $PriorState
    $status | Add-Member -NotePropertyName StopRequested -NotePropertyValue $StopRequested
    $status | Add-Member -NotePropertyName StopCompleted -NotePropertyValue $StopCompleted
    $status | Add-Member -NotePropertyName RunspaceClosed -NotePropertyValue $RunspaceClosed
    $status | Add-Member -NotePropertyName AlreadyTerminal -NotePropertyValue $AlreadyTerminal
    return $status
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
            CancellationAcknowledged = $false
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
        [switch]$RemoveAfterReceive,
        [switch]$AcknowledgeIntentionalCancellation,
        [ValidateRange(0, 300000)][int]$TimeoutMilliseconds = 0
    )

    $opSignal = [Signal]::Start('Receive-STBackgroundTask', $Signal) | Select-Object -Last 1
    if (-not $script:STBackgroundTasks.ContainsKey($TaskId)) {
        $null = $opSignal.LogCritical("Background task '$TaskId' was not found.")
        return $opSignal
    }

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        $updateSignal = Update-STBackgroundTasks -Signal $opSignal | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($updateSignal)) { return $opSignal }
        $task = $script:STBackgroundTasks[$TaskId]
        if ($task.State -notin @('Queued', 'Running') -or -not $Wait) { break }
        if ($TimeoutMilliseconds -gt 0) {
            $remaining = $TimeoutMilliseconds - $timer.ElapsedMilliseconds
            if ($remaining -le 0) {
                $null = $opSignal.LogCritical("Background task '$TaskId' timed out after $TimeoutMilliseconds ms in state '$($task.State)'.")
                return $opSignal
            }
            Start-Sleep -Milliseconds ([int][Math]::Min(100, $remaining))
        }
        else { Start-Sleep -Milliseconds 100 }
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
    if ($task.State -eq 'Failed' -or
        ($task.State -eq 'Cancelled' -and -not ($AcknowledgeIntentionalCancellation -and $task.CancellationAcknowledged))) {
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
        [switch]$MergeWorkerSignals,
        [ValidateRange(0, 300000)][int]$TimeoutMilliseconds = 0
    )

    $opSignal = [Signal]::Start('Wait-STBackgroundTasks', $Signal) | Select-Object -Last 1
    $ids = @($script:STBackgroundTasks.Values | Where-Object { [string]::IsNullOrWhiteSpace($OwnerId) -or $_.OwnerId -eq $OwnerId } | ForEach-Object TaskId)
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $results = foreach ($id in $ids) {
        $remaining = if ($TimeoutMilliseconds -gt 0) { [int]($TimeoutMilliseconds - $timer.ElapsedMilliseconds) } else { 0 }
        if ($TimeoutMilliseconds -gt 0 -and $remaining -le 0) {
            $updateSignal = Update-STBackgroundTasks -Signal $opSignal | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure($updateSignal)) { return $opSignal }
            $pending = @($ids | Where-Object { $script:STBackgroundTasks.ContainsKey($_) -and $script:STBackgroundTasks[$_].State -in @('Queued', 'Running') } | ForEach-Object { "$($_):$($script:STBackgroundTasks[$_].State)" })
            if ($pending.Count -gt 0) {
                $null = $opSignal.LogCritical("Background tasks timed out after $TimeoutMilliseconds ms. Pending: $($pending -join ', ').")
                return $opSignal
            }
            $remaining = 1
        }
        $receiveSignal = Receive-STBackgroundTask -TaskId $id -Signal $opSignal -Wait -RemoveAfterReceive:$RemoveAfterReceive -AcknowledgeIntentionalCancellation:$MergeWorkerSignals -TimeoutMilliseconds $remaining | Select-Object -Last 1
        $null = $opSignal.MergeSignal($receiveSignal)
        if ($receiveSignal.Failure()) {
            $pending = @($ids | Where-Object { $script:STBackgroundTasks.ContainsKey($_) -and $script:STBackgroundTasks[$_].State -in @('Queued', 'Running') } | ForEach-Object { "$($_):$($script:STBackgroundTasks[$_].State)" })
            if ($pending.Count -gt 0) { $null = $opSignal.LogCritical("Pending owned background tasks: $($pending -join ', ').") }
            return $opSignal
        }
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
    $priorState = [string]$task.State
    if ($priorState -in @('Completed', 'Failed', 'Cancelled')) {
        $opSignal.SetResult((ConvertTo-STBackgroundStopStatus $task $priorState $false $false $null $true))
        return $opSignal
    }
    if ($priorState -eq 'Queued') {
        $task.State = 'Cancelled'
        $task.CompletedUtc = [DateTime]::UtcNow
        $task.CancellationAcknowledged = $true
        $opSignal.SetResult((ConvertTo-STBackgroundStopStatus $task $priorState $true $true $true $false))
        return $opSignal
    }
    if ($priorState -ne 'Running' -or $null -eq $task.PowerShell -or $null -eq $task.Runspace -or $null -eq $task.Handle) {
        $null = $opSignal.LogCritical("Background task '$TaskId' has an unsupported or incomplete active state '$priorState'; ownership retained.")
        return $opSignal
    }
    if ($task.Handle.IsCompleted) {
        $null = $opSignal.LogCritical("Background task '$TaskId' has completed but is pending finalization; use GetPhaseStatus or AwaitPhase. Ownership retained.")
        return $opSignal
    }
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $stopTask = $task.PowerShell.StopAsync($null, $null)
        if (-not $stopTask.Wait(30000)) { throw 'StopAsync did not complete within 30000 ms.' }
        $null = $stopTask.GetAwaiter().GetResult()
        if ($task.PowerShell.InvocationStateInfo.State -ne [System.Management.Automation.PSInvocationState]::Stopped) {
            throw "StopAsync completed with PowerShell state '$($task.PowerShell.InvocationStateInfo.State)', not Stopped."
        }
        $task.Runspace.CloseAsync()
        while ($task.Runspace.RunspaceStateInfo.State -ne [System.Management.Automation.Runspaces.RunspaceState]::Closed) {
            if ($task.Runspace.RunspaceStateInfo.State -eq [System.Management.Automation.Runspaces.RunspaceState]::Broken) {
                throw 'Runspace became broken during CloseAsync.'
            }
            if ($timer.ElapsedMilliseconds -ge 30000) { throw 'CloseAsync did not close within the remaining 30000 ms budget.' }
            Start-Sleep -Milliseconds ([int][Math]::Min(100, 30000 - $timer.ElapsedMilliseconds))
        }
        $task.PowerShell.Dispose()
        $task.Runspace.Dispose()
    }
    catch {
        $null = $opSignal.LogCritical("Failed to stop background task '$TaskId'; ownership retained: $($_.Exception.Message)", $null, $_)
        return $opSignal
    }
    $task.PowerShell = $null
    $task.Runspace = $null
    $task.Handle = $null
    $task.State = 'Cancelled'
    $task.CompletedUtc = [DateTime]::UtcNow
    $task.CancellationAcknowledged = $true
    $opSignal.SetResult((ConvertTo-STBackgroundStopStatus $task $priorState $true $true $true $false))
    return $opSignal
}
