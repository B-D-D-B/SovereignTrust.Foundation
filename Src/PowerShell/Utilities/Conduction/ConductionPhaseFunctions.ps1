

function Realize-ConductionPhase {
    param (
        [Parameter(Mandatory)][object]$PhaseSettings,
        [Parameter(Mandatory)][object]$HydratedMemory,
        [Parameter(Mandatory)][object]$ConductionSignalFeedback,
        [Parameter(Mandatory)][object]$PhaseDictionary,
        [Parameter(Mandatory)][object]$ConduitContext
    )

    $signal = [Signal]::Start("Realize-ConductionPhase") | Select-Object -Last 1

    try {
        $resolvedSettings = $HydratedMemory
        $signal.SetResult(@{
            Settings       = $resolvedSettings
            PhaseSettings  = $PhaseSettings
            SignalFeedback = $ConductionSignalFeedback
            PhaseDictionary = $PhaseDictionary
            Conduit        = $ConduitContext
        })

        $signal.LogInformation("✅ Phase realized from memory and settings.")
    }
    catch {
        $signal.LogCritical("🔥 Exception: Failed to realize conduction phase: $_", $null, $_)
    }

    return $signal
}

function Get-ConductionStatusFromPhase {
    param (
        [Parameter(Mandatory)][object]$PhaseSettings,
        [Parameter(Mandatory)][string]$LogType,
        [bool]$IsFailure = $false
    )

    $status = "UNSPECIFIED"

    if ($PhaseSettings.PhaseEventLoggingType -eq "Unspecified") {
        return $status
    }

    if ($LogType -eq "Before" -and $PhaseSettings.PhaseEventLoggingType -ne "After") {
        $status = $PhaseSettings.StartStatusCode
    }
    elseif ($LogType -eq "After" -and $PhaseSettings.PhaseEventLoggingType -ne "Before") {
        if ($IsFailure) {
            $status = $PhaseSettings.FailureStatusCode
        }
        else {
            $status = $PhaseSettings.SuccessStatusCode
        }

        if ($status -eq "UNSPECIFIED") {
            $status = $PhaseSettings.StartStatusCode
        }
    }

    return $status
}

function Set-ConductionFeedback {
    param (
        [Parameter(Mandatory)][object]$PhaseContext,
        [Parameter(Mandatory)][object]$Feedback
    )

    $PhaseContext.ConductionFeedback = $Feedback
    return $PhaseContext
}

function Set-ConductionResult {
    param (
        [Parameter(Mandatory)][object]$PhaseContext,
        [Parameter(Mandatory)][object]$Result
    )

    $PhaseContext.ConductionResult = $Result
    return $PhaseContext
}
