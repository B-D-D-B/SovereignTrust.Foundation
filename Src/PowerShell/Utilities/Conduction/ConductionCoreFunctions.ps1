

function Realize-ConductionPhase {
    param (
        [Parameter(Mandatory)][object]$PhaseSettings,
        [Parameter(Mandatory)][hashtable]$TypeDictionary,
        [Parameter(Mandatory)][object]$Trigger,
        [Parameter(Mandatory)][object]$ConductionFeedback,
        [Parameter(Mandatory)][object]$ConductionResult,
        [Parameter(Mandatory)][object]$ConduitJacket,
        [Parameter(Mandatory)][hashtable]$PhaseDictionary
    )

    $signal = [Signal]::Start([IConductionPhase]) | Select-Object -Last 1
    try {
        $typeName = $PhaseSettings.PhaseType
        if (-not $TypeDictionary.ContainsKey($typeName)) {
            $signal.LogCritical("Phase Type '$typeName' not found in dictionary.")
            return $signal
        }

        $type = $TypeDictionary[$typeName]
        $phase = New-Object $type
        $null = $phase.Realize($Trigger, $ConductionFeedback, $ConductionResult, $ConduitJacket, $PhaseSettings, $ConductionResult, $PhaseDictionary)
        $signal.SetResult($phase)
    } catch {
        $signal.LogCritical("Failed to realize conduction phase: $_")
    }

    return $signal
}

function Get-NextConductionPhase {
    param (
        [Parameter()][object]$CurrentPhase,
        [Parameter(Mandatory)][hashtable]$PhaseDictionary
    )

    $signal = [Signal]::Start([IConductionPhase]) | Select-Object -Last 1
    $phases = $PhaseDictionary.Values

    if (-not $CurrentPhase) {
        $signal.Result = $phases | Where-Object { $_.PhaseSettings.IsStartingPhase } | Select-Object -First 1
        if (-not $signal.Result) {
            $signal.Result = $phases | Where-Object { -not $_.PhaseSettings.IsFailurePhase } | Select-Object -First 1
        }
    } else {
        if ($CurrentPhase.ConductionSignalFeedback.Failure) {
            $signal.Result = $phases | Where-Object { $_.PhaseSettings.Name -eq $CurrentPhase.PhaseSettings.OnFailPhase } |
                             Select-Object -First 1
            if (-not $signal.Result) {
                $signal.Result = $phases | Where-Object { $_.PhaseSettings.IsFailurePhase } | Select-Object -First 1
            }
        } else {
            $signal.Result = $phases | Where-Object { $_.PhaseSettings.Name -eq $CurrentPhase.PhaseSettings.OnSuccessPhase } |
                             Select-Object -First 1
            if (-not $signal.Result) {
                $currentIndex = ($phases.IndexOf($CurrentPhase))
                $signal.Result = $phases[$currentIndex + 1]
            }
        }
    }

    return $signal
}

function Manage-ConductionResult {
    param (
        [Parameter(Mandatory)][object]$ProcessContainer,
        [Parameter()][object]$Trigger,
        [Parameter(Mandatory)][object]$ConductionFeedback,
        [Parameter(Mandatory)][object]$Signal,
        [string]$FileSuffix = "",
        [bool]$ClearOperationLog = $false
    )

    try {
        $identifier = $Trigger?.LastConduction?.ConductionIdentifier
        if (-not $identifier) {
            $identifier = $ConductionFeedback.ConductionIdentifier
        }

        if ($identifier -and $identifier -ne [Guid]::Empty) {
            $null = $ProcessContainer.StorageJacketService.ManageExecutionResult($Signal, $identifier, $FileSuffix, [System.Threading.CancellationToken]::None)
            if ($ClearOperationLog) {
                $Signal.Entries.Clear()
            }
        }
    } catch {
        $Signal.LogCritical("Failed to manage conduction result: $_")
    }
}

function Manage-IntervalConductionResult {
    param (
        [Parameter(Mandatory)][object]$ProcessContainer,
        [Parameter()][object]$Trigger,
        [Parameter(Mandatory)][object]$ConductionFeedback,
        [Parameter(Mandatory)][object]$VerboseResult,
        [Parameter(Mandatory)][object]$FinalResult,
        [Parameter(Mandatory)][object]$Phase,
        [bool]$ClearOperationLog = $false
    )

    $message = $null
    if ($VerboseResult.Entries.Count -gt 0) {
        $suffix = "_" + $Phase.PhaseSettings.Name.Replace(" ", "")
        $message = "$($Phase.PhaseSettings.Name) Verbose log stored: $($ConductionFeedback.ConductionIdentifier)$suffix"
        Manage-ConductionResult -ProcessContainer $ProcessContainer -Trigger $Trigger -ConductionFeedback $ConductionFeedback -Signal $VerboseResult -FileSuffix $suffix -ClearOperationLog:$ClearOperationLog
    }

    if ($message) {
        $FinalResult.LogInformation($message)
    }

    return $message
}
