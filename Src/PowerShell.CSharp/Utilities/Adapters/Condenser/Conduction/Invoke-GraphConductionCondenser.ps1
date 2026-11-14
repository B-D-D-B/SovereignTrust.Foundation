# =============================================================================
# 📍 Invoke-GraphConductionCondenser (Declarative Graph Builder + Injector)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☠️🧁👾️/🤖 • Neural Alchemist ⚗️☣️🐲 • Last Generated: 06/25/2025
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

function Invoke-GraphConductionCondenser {
    param (
        [Signal]$Signal,
        [object]$Plan,
        [object]$ItemSignal,
        [string]$PlanWirePathPrefix = "%.%.%.@"  # <- new param with default
    )

    $opSignal = [Signal]::Start("Invoke-GraphConductionCondenser:$Plan.Name", $Signal) | Select-Object -Last 1

    $PlanName = $Plan.Name
    $subSignal = [Signal]::Start("GraphPlan:$PlanName", $Signal) | Select-Object -Last 1
    $subSignal.SetJacket($ItemSignal) | Out-Null


    #Check to see if the ItemSignal (The Conduction Signal) has a Grid. If so, then we can go to the step of executing the conduction graph. 

    $JacketSignalWrapper = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%" | Select-Object -Last 1
    
    $JacketSignal = $JacketSignalWrapper.GetResult()

    $hydrationSignal = Invoke-ApplyHydrationCondenser -Signal  $Signal -Plan $Plan -ItemSignal $JacketSignal -HydrationStyle "Deferred" | Select-Object -Last 1

    #    $ResolveAdapterSignal = Resolve-AdapterFromJacket -ConductionContext $Signal -Signal $Signal -Jacket $JacketSignal | Select-Object -Last 1

    $wrappedGraphSignal = [Signal]::Start("Graph:$PlanName", $Signal) | Select-Object -Last 1

    $sourcePathSignal = Resolve-SourcePathFromPlan -plan $Plan | Select-Object -Last 1

    $conductionPlanSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $sourcePathSignal.GetResult() | Select-Object -Last 1

    $GridPlan = [PSCustomObject]@{
        SourcesWirePath = "ConductionPlan"
        SourcesWirePathTemplate = "%.%.@.{0}"
        SourcesIdentifierWirePath = "Name"
    }

    $ConductionPlanWrapperSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%.@"  | Select-Object -Last 1
    $ConductionSlotSignal = Resolve-PathFromDictionary -Dictionary $ConductionPlanWrapperSignal.GetResult() -Path "ConductionType"  | Select-Object -Last 1

    $slot = $ConductionSlotSignal.GetResult()

    $gridConductionPlanSignal = Invoke-GridCondenser -Signal $Signal -Plan $GridPlan -ItemSignal $ItemSignal -PlanWirePathPrefix "%.%.@" | Select-Object -Last 1
   
    $gridConductionPlan = Resolve-PathFromDictionary -Dictionary $gridConductionPlanSignal -Path "@.*" | Select-Object -Last 1

#    $ItemSignal.SetPointer($gridConductionPlan.GetResult()) | Out-Null

   $mappedConductionPath = "%.*.#.Adapters.*.#.MappedConduction"

    $AdapterSignal = Resolve-PathFromDictionary -Dictionary $Signal -Path $mappedConductionPath | Select-Object -Last 1
 
    if ($opSignal.MergeSignalAndVerifyFailure($adapterResultSignal)) {
        $opSignal.LogCritical("❌ MappedConduction Adapter not found at path '$mappedConductionPath'. Ensure the Conductor has been initialized with the MappedConductionAdapter.")
        return $opSignal
    }

    $Adapter = $AdapterSignal.GetResult() | Select-Object -Last 1

    while ($Adapter -is [Signal]) {
        $Adapter = $Adapter.GetResult()
    }

    $conductionSignal = [Signal]::Start("Conduction:Signal", $Signal) | Select-Object -Last 1
    $conductionSignal.SetPointer($gridConductionPlan.GetResult()) | Out-Null
    $conductionSignal.SetJacket($ItemSignal.GetJacket()) | Out-Null
 
    $adapterResultSignal = $Adapter.Invoke($slot, $conductionSignal, $Plan) | Select-Object -Last 1

    if ($opSignal.MergeSignalAndVerifyFailure($adapterResultSignal)) {
        $opSignal.LogCritical("❌ Failed to execute MappedConduction Adapter for plan '$PlanName'.")
        return $opSignal
    }



#    $ConductionResult = Invoke-ConductionCondenser -Signal $ConductionSignal -Plan $Plan -ItemSignal $ItemSignal | Select-Object -Last 1



    if ($Plan.TargetWirePath) {
        $injectSignal = Add-PathToDictionary -Dictionary $ItemSignal -Path $Plan.TargetWirePath -Value $Adapter | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($injectSignal)) {
            $opSignal.LogCritical("❌ Failed to inject graph into '$($Plan.TargetWirePath)'")
            return $opSignal
        }
        $opSignal.LogInformation("📍 Injected graph '$PlanName' into '$($Plan.TargetWirePath)'")
    }


    <#
    $addPlanSignal = Add-PathToDictionary -Dictionary $subSignal -Path "${PlanWirePathPrefix}.Plan" -Value $Plan | Select-Object -Last 1
    if ($opSignal.MergeSignalAndVerifyFailure($addPlanSignal)) {
        $opSignal.LogCritical("❌ Failed to attach Plan to subSignal at path ${PlanWirePathPrefix}.Plan")
        return $opSignal
    }

    $graphSignal = Resolve-PathGraphForJsonArray -ConductionSignal $subSignal | Select-Object -Last 1
    if ($opSignal.MergeSignalAndVerifyFailure($graphSignal)) {
        $opSignal.LogWarning("Failed to resolve graph for plan: $PlanName")
        return $opSignal
    }

    $graphResult = $graphSignal.GetResult()

    $wrappedGraphSignal = [Signal]::Start("Graph:$PlanName", $Signal) | Select-Object -Last 1
    $wrappedGraphSignal.SetPointer($graphResult) | Out-Null

    if ($Plan.TargetWirePath) {
        $injectSignal = Add-PathToDictionary -Dictionary $ItemSignal -Path $Plan.TargetWirePath -Value $wrappedGraphSignal | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($injectSignal)) {
            $opSignal.LogCritical("❌ Failed to inject graph into '$($Plan.TargetWirePath)'")
            return $opSignal
        }
        $opSignal.LogInformation("📍 Injected graph '$PlanName' into '$($Plan.TargetWirePath)'")
    }
    $opSignal.SetResult($wrappedGraphSignal)
#>

    $opSignal.LogInformation("✅ Graph Conduction plan '$PlanName' completed successfully.")
    return $opSignal
}
