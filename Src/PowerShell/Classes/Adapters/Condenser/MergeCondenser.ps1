# =============================================================================
# 🔄 MergeCondenser (Declarative Memory Overlay & Unification Engine)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☠️🧁👾️/🤖 • Neural Alchemist ⚗️☣️🐲 • Last Updated: 05/20/2025
# =============================================================================
# Performs recursive, additive overlay merging between structured sovereign memory types.
#
# This includes support for:
# - Hashtables (raw objects)
# - Signals (Jacket-bound memory containers)
# - Graphs (living memory meshes)
#
# TODO: Replace [Signal]$Signal with [Graph]$SignalGraph to enable sovereign lineage tracking.
#       Each method should register its signal as a node in the Graph using RegisterSignal().
#       This elevates the signal from a linear log to a queryable, memory-safe signal map.
#
# Doctrine Alignment:
# • Sovereign Memory: ✅
# • Living Signals: ✅
# • Adapter Evolution: ✅
# • Temporal Recursion: ✅
# =============================================================================

class MergeCondenser {
    [Conductor]$Conductor
    [MappedCondenserAdapter]$MappedCondenserAdapter
    [Signal]$Signal  # Sovereign control signal (previously ControlSignal)

    MergeCondenser() {
    }

    static [MergeCondenser] Start([MappedCondenserAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [MergeCondenser]::new()
        $instance.MappedCondenserAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("MergeCondenser.Control") | Select-Object -Last 1
        return $instance
    }

[Signal]Invoke(
    [string]$Slot,
    [string]$Activity,
    [Signal]$ConductionSignal,
    [object]$Plan,
    [Signal]$ItemSignal
) {
    $opSignal = [Signal]::Start("MemoryCondenser.Invoke:Transform.Merge", $ItemSignal) | Select-Object -Last 1

    try {
        # ---- Resolve plan options (with sane defaults) ----
        $mergeNullValueHandlingSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "MergeNullValueHandling" -Default "Ignore"  -SignalLevel "Warning" | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure(@($mergeNullValueHandlingSignal))) { return $opSignal }
        $MergeNullValueHandling = $mergeNullValueHandlingSignal.GetResult()

        $mergeArrayHandlingSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "MergeArrayHandling" -Default "Merge" -SignalLevel "Warning" | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure(@($mergeArrayHandlingSignal))) { return $opSignal }
        $MergeArrayHandling = $mergeArrayHandlingSignal.GetResult()

        $depthSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Depth" -Default 20 -SignalLevel "Warning" | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure(@($depthSignal))) { return $opSignal }
        $Depth = $depthSignal.GetResult()

        # ---- Resolve inputs from ItemSignal jacket/result ----
        $baseSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%.@.Base" -SignalLevel "Critical" | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure(@($baseSignal))) { return $opSignal }
        if (-not $baseSignal.HasResult()) {
            $opSignal.LogCritical("Missing required merge input: Base")
            return $opSignal
        }
        $Base = $baseSignal.GetResult()

        $overlaySignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%.@.Overlay" -SignalLevel "Critical" | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure(@($overlaySignal))) { return $opSignal }
        if (-not $overlaySignal.HasResult()) {
            $opSignal.LogCritical("Missing required merge input: Overlay")
            return $opSignal
        }
        $Overlay = $overlaySignal.GetResult()

        # ---- Execute merge ----
        $resultSignal = Invoke-MergeJson `
            -Base $Base `
            -Overlay $Overlay `
            -MergeArrayHandling $MergeArrayHandling `
            -MergeNullValueHandling $MergeNullValueHandling `
            -Depth $Depth `
        | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure(@($resultSignal))) { return $opSignal }

        $opSignal.SetResult($resultSignal.GetResult())
        $opSignal.LogInformation("✅ Merge completed.")
        return $opSignal
    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Merge: $($_.Exception.Message)", $null, $_)
        return $opSignal
    }
}
<#
    # Should we move Merge function into TransformCondenser?
    [Signal] MergeJsonObject([Signal]$opSignal, [object]$Base, [object]$Overlay, [string]$MergeArrayHandling, [string]$MergeNullValueHandling, [int]$Depth, [bool]$IgnoreInternalObjects = $true) {
        $opSignal = $opSignal ?? ([Signal]::Start("MergeCondenser.Merge") | Select-Object -Last 1)

        return Invoke-MergeJson -OpSignal $OpSignal -Base $Base -Overlay $Overlay -MergeArrayHandling $MergeArrayHandling -MergeNullValueHandling $MergeNullValueHandling -Depth $Depth | Select-Object -Last 1
    }

    [Signal] InvokeByParameter([object]$Base, [object]$Overlay, [bool]$IgnoreInternalObjects = $true) {
        $opSignal = [Signal]::Start("MergeCondenser.Invoke-ByParameter") | Select-Object -Last 1

        $mergeSignal = Invoke-TransformCondenserUnifiedMemory -Base $Base -Overlay $Overlay | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifySuccess($mergeSignal)) {
            $opSignal.SetResult($mergeSignal.GetResult())
            $opSignal.LogInformation("✅ Merge completed successfully via unified invocation.")
        }
        else {
            $opSignal.LogWarning("Merge operation failed in Invoke-ByParameter.")
        }

        $this.Signal.MergeSignal($opSignal)
        return $opSignal
    } #>
}
