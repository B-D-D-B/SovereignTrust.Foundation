# ░▒▓════════════════════════════════════════════════════════════════════▓▒░
# File: Convert-AgentAdaptersToConductor.ps1 • Project: SovereignTrust Core
# License: MIT • Authors: Shadow PhanTom, Neural Alchemist • Generated: 2025-04-30
# Lineage: SovereignTrust.Foundation.Adapters.Convert-AgentAdaptersToConductor
# ░▒▓════════════════════════════════════════════════════════════════════▓▒░
# 🧠 SIGNAL USAGE EXEMPLAR
# This file demonstrates the full spectrum of SovereignTrust signal recursion patterns:
#   • 📦 Structured Signal creation, propagation, and conditional merging
#   • 🔁 Flow-controlled MergeSignalAndVerifySuccess with optional mute gates
#   • ❌ Critical logging for invalid invocation and halt conditions
#   • 🛠 Recovery-based de-escalation via LogRecovery for self-healing surfaces
#   • 🔕 Conditional muting of expected Criticals via LogMute (non-blocking trace carry)
#   • 🧱 Sovereign-safe dictionary construction with signal-confirmed adapter
#   • 📚 Result memory adapter and lineage export via SetResult
#
# ✅ Recommended as the reference exemplar for memory-driven initialization logic,
#    and a canonical implementation of sovereign flow using living Signals.


function Convert-AgentAdaptersToConductor {
    param (
        [Parameter(Mandatory = $true)]
        [object]$Agent,

        [Parameter(Mandatory = $true)]
        [string]$RoleName,


        [Parameter(Mandatory = $true)]
        [object]$Conductor
    )

    $signal = [Signal]::Start("Convert-AgentAdaptersToConductor") | Select-Object -Last 1

    function Add-AdapterJacket {
        param (
            [string]$name,
            [object]$jacket
        )
        $addSignal = Add-PathToDictionary -Dictionary $Conductor -Path "AdapterJackets.$name" -Value $jacket | Select-Object -Last 1
        if ($signal.MergeSignalAndVerifySuccess($addSignal)) {
            $signal.LogVerbose("Mapped Adapter Jacket: $name")
        } else {
            $signal.LogWarning("Failed to map adapter jacket: $name")
        }
    }

    try {
        if (-not $Agent) {
            $signal.LogCritical("Agent is null. Cannot process adapters.")
            return $signal
        }

        if (-not $Conductor) {
            $signal.LogCritical("Conductor is null. Cannot assign adapters.")
            return $signal
        }

        # ░▒▓█ INITIALIZE ATTACHMENTJACKETS MEMORY █▓▒░
        $adapterJacketsSignal = Resolve-PathFromDictionary -Dictionary $Conductor -Path "AdapterJackets" | Select-Object -Last 1
        if (-not $signal.MergeSignalAndVerifySuccess($adapterJacketsSignal)) {
            $initSignal = Add-PathToDictionary -Dictionary $Conductor -Path "AdapterJackets" -Value ([System.Collections.Generic.List[object]]::new()) | Select-Object -Last 1
            if ($signal.MergeSignalAndVerifySuccess($initSignal)) {
                $signal.LogRecovery("🔁 AdapterJackets path was missing but was recovered via initialization.")
            } else {
                $signal.LogWarning("Failed to initialize AdapterJackets memory space.")
            }
        }

        # ░▒▓█ AGENT ROLE ATTACHMENTS █▓▒░
        $roleAdaptersSignal = Resolve-PathFromDictionary -Dictionary $Agent -Path "Roles.$RoleName.Adapters" | Select-Object -Last 1
        if ($signal.MergeSignalAndVerifySuccess($roleAdaptersSignal, $true, "Adapters are optional and were safely muted.")) {
            $roleAdapters = $roleAdaptersSignal.GetResult()
            foreach ($roleAdapterJacket in $roleAdapters) {
                if ($roleAdapterJacket.Name) {
                    Add-AdapterJacket -name $roleAdapterJacket.Name -jacket $roleAdapterJacket
                } else {
                    $signal.LogWarning("Skipped Role adapter jacket with missing name.")
                }
            }
            $signal.LogRecovery("Role-level adapter jackets migrated to Conductor.")
        }

        $signal.SetResult($Conductor)
    }
    catch {
        $signal.LogCritical("Exception: critical failure in Convert-AgentAdaptersToConductor: $($_.Exception.Message)", $null, $_)
    }

    return $signal
}
