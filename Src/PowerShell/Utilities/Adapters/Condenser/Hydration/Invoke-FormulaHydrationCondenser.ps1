# =============================================================================
# 📍 Invoke-FormulaHydrationCondenser (Declarative Token Hydration Injector)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☠️🧁👾️/🤖 • Neural Alchemist ⚗️☣️🐲 • Last Generated: 07/10/2025
# =============================================================================
# Performs hydration according to a formula graph. 
# If no formula graph is provided, it will use the default hydration condenser settings of using a Mini-Map -> Token Recursion.
#
# Inputs:
#
# Process:
#   - Iterates through a formula graph if provided, if not, generates one to iterate until all tokens are hydrated.
#
# Output:
#   - Returns the wrapped Signal with .Pointer to the constructed graph
#
# All operations respect sovereign memory principles:
# - No raw object mutation
# - All lineage is tracked through Signals
# - Memory injection is explicit and symbolic

function Invoke-FormulaHydrationCondenser {
    param (
        [Signal]$Signal,
        [string]$Content
    )

    $opSignal = [Signal]::Start("Invoke-FormulaHydrationCondenser", $Signal) | Select-Object -Last 1

    $PlanName = $Plan.Name
    $subSignal = [Signal]::Start("GraphPlan:$PlanName", $Signal) | Select-Object -Last 1
    $subSignal.SetJacket($ItemSignal) | Out-Null

    $addPlanSignal = Add-PathToDictionary -Dictionary $subSignal -Path "${PlanWirePathPrefix}.Plan" -Value $Plan | Select-Object -Last 1
    if ($opSignal.MergeSignalAndVerifyFailure($addPlanSignal)) {
        $opSignal.LogCritical("❌ Failed to attach Plan to subSignal at path ${PlanWirePathPrefix}.Plan")
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
            $opSignal.LogCritical("❌ Failed to inject graph into '$($Plan.TargetWirePath)'")
            return $opSignal
        }
        $opSignal.LogInformation("📍 Injected graph '$PlanName' into '$($Plan.TargetWirePath)'")
    }

    $opSignal.SetResult($wrappedGraphSignal)
    $opSignal.LogInformation("✅ Graph plan '$PlanName' completed successfully.")
    return $opSignal
}
