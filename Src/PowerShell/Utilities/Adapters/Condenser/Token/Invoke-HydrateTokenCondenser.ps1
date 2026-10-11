# =============================================================================
# 📍 Invoke-JsonTokenCondenser (Declarative Token Hydration Injector)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☠️🧁👾️/🤖 • Neural Alchemist ⚗️☣️🐲 • Last Generated: 07/10/2025
# =============================================================================
# This function performs a single declarative execution of a graph plan over a 
# scoped memory object, returning a wrapped Signal with a `.Pointer` to the 
# constructed graph. It is designed for use inside a recursive formula graph 
# condenser loop, and supports injection of the graph signal into a declared 
# memory wire path if `TargetWirePath` is specified.
#
# Inputs:
#   - ParentSignal: the governing signal scope (used for escalation and lineage)
#   - Plan: a GraphFormulaPlan containing Source/Sources/Target fields
#   - Item: the scoped JSON object or memory jacket to apply the plan against
#   - PlanName: the declared name of the plan (used for logging + signal identity)
#
# Process:
#   - Creates a scoped sub-signal with jacket and plan metadata
#   - Runs Resolve-PathGraphForJsonArray to generate graph
#   - Wraps result in a new Signal with .Pointer set
#   - Injects signal into memory if TargetWirePath is defined
#
# Output:
#   - Returns the wrapped Signal with .Pointer to the constructed graph
#
# All operations respect sovereign memory principles:
# - No raw object mutation
# - All lineage is tracked through Signals
# - Memory injection is explicit and symbolic

function Invoke-HydrateTokenCondenser {
    param (
        [Signal]$Signal,
        [object]$Plan,
        [object]$ItemSignal,
        [string]$PlanWirePathPrefix = "%.%.%.@"  # <- new param with default
    )

    $opSignal = [Signal]::Start("Invoke-GridCondenser:$PlanName", $Signal) | Select-Object -Last 1

    $PlanName = $Plan.Name
    $subSignal = [Signal]::Start("GraphPlan:$PlanName", $Signal) | Select-Object -Last 1
    $subSignal.SetJacket($ItemSignal) | Out-Null

    $addPlanSignal = Add-PathToDictionary -Dictionary $subSignal -Path "${PlanWirePathPrefix}.Plan" -Value $Plan | Select-Object -Last 1
    if ($opSignal.MergeSignalAndVerifyFailure($addPlanSignal)) {
        $opSignal.LogCritical("Failed to attach Plan to subSignal at path ${PlanWirePathPrefix}.Plan")
        return $opSignal
    }

    ##### Hydration Step
    $graphSignal = Resolve-PathGraphForJsonArray -ConductionSignal $subSignal | Select-Object -Last 1
    if ($opSignal.MergeSignalAndVerifyFailure($graphSignal)) {
        $opSignal.LogWarning("Failed to resolve graph for plan: $PlanName")
        return $opSignal
    }

    $graphResult = $graphSignal.GetResult()

    $wrappedGraphSignal = [Signal]::Start("Graph:$PlanName", $Signal) | Select-Object -Last 1
    $wrappedGraphSignal.SetPointer($graphResult) | Out-Null

    # Option to replace Jacket or other location with the output that is going into the opSignal result. (to replace the $graphSignal)
    if ($Plan.TargetWirePath) {
        $injectSignal = Add-PathToDictionary -Dictionary $ItemSignal -Path $Plan.TargetWirePath -Value $wrappedGraphSignal | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($injectSignal)) {
            $opSignal.LogCritical("Failed to inject graph into '$($Plan.TargetWirePath)'")
            return $opSignal
        }
        $opSignal.LogInformation("📍 Injected graph '$PlanName' into '$($Plan.TargetWirePath)'")
    }

    $opSignal.SetResult($wrappedGraphSignal)
    $opSignal.LogInformation("✅ Graph plan '$PlanName' completed successfully.")
    return $opSignal
}
