# =============================================================================
# 🚦 Invoke-ConductionCondenser
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☚️🐝🤖/ • Neural Alchemist ⚗️☣️🐲 • Version: 2025.5.22
# =============================================================================
# Invokes Conduction phase processing using a sovereign Graph structure and
# interprets each Phase block in sequence or via branching (OnSuccess / OnFail).
# Compatible with the SDA GridCondenser pipeline and sovereign runtime standards.
# =============================================================================Thank

function Invoke-ConductionCondenser {
    [CmdletBinding()]
    param (
        [Signal]$Signal,
        [object]$Plan,
        [object]$ItemSignal,
        [string]$PlanWirePathPrefix = "%.%.%.@"  # <- new param with default
    )

    $opSignal = [Signal]::Start("Invoke-ConductionCondenser", $Signal) | Select-Object -Last 1


    $sourcePathSignal = Resolve-SourcePathFromPlan -plan $Plan | Select-Object -Last 1

   # Conduction Condenser needs to call the Mapped Conduction Adapter and pass through the steps.

    $conductionPlanSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $sourcePathSignal.GetResult() | Select-Object -Last 1

    $conductionPlan = $conductionPlanSignal.GetResult()
        
    $phaseDictSignal = Resolve-PathFromDictionary -Dictionary $conductionPlan -Path "PhaseDictionary" | Select-Object -Last 1
    if ($opSignal.MergeSignalAndVerifyFailure($phaseDictSignal)) {
        return $opSignal.LogCritical("PhaseDictionary not found in Graph.")
    }

    $phaseDict = $phaseDictSignal.GetResult()
    $phaseKeys = $phaseDict.Keys
    $phaseIndex = 0

    while ($phaseIndex -lt $phaseKeys.Count) {
        $phaseKey = $phaseKeys[$phaseIndex]
        $phase = $phaseDict[$phaseKey]
        $stepSignal = [Signal]::Start("Phase:$phaseKey", $Signal) | Select-Object -Last 1

        $stepType = $phase.Type
        switch ($stepType) {
            "Command" {
                $cmd = $phase.Command
                try {
                    $result = Invoke-Expression $cmd
                    $stepSignal.SetResult($result)
                    $stepSignal.LogInformation("✅ Command executed for phase: $phaseKey")
                } catch {
                    $stepSignal.LogCritical("🔥 Exception in command phase '$phaseKey': $($_.Exception.Message)", $null, $_)
                }
            }
            default {
                $stepSignal.LogWarning("Unknown phase type '$stepType' in phase '$phaseKey'")
            }
        }

        $opSignal.MergeSignal($stepSignal)

        if ($stepSignal.Failure()) {
            if ($phase.OnFailPhase) {
                $phaseIndex = $phaseKeys.IndexOf($phase.OnFailPhase)
                continue
            }
        }
        else {
            if ($phase.OnSuccessPhase) {
                $phaseIndex = $phaseKeys.IndexOf($phase.OnSuccessPhase)
                continue
            }
        }

        $phaseIndex++
    }

    $opSignal.LogInformation("✅ Conduction phases executed.")
    return $opSignal
}
