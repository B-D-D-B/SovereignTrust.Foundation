# =============================================================================
# 🧪 GraphCondenser (Declarative Multi-Plan Graph Launcher)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☠️🧁👾️/🤖 • Neural Alchemist ⚗️☣️🐲 • Last Generated: 06/25/2025
# =============================================================================
# The GraphCondenser is a memory-driven execution class that consumes
# declarative GraphPlans from sovereign memory, processes them via the SDA
# graph condenser pipeline, and injects the resulting graph signals into 
# structured runtime memory.
#
# It is designed for recursive, multi-agent, or adapter-based plan hydration,
# and supports both default (%.*.FlatFormulaSource) and direct wire path 
# triggering (e.g., %.%.%.@.GraphFormulas.Agents).
#
# Structure:
#   - Conductor: the executing memory host (contains signal + pointer memory)
#   - MappedCondenserAdapter: source of hydration condensers and plan logic
#   - Signal: sovereign control and lineage vessel
#
# Core Methods:
#   - Invoke(): Launches a top-level plan hydration from FlatFormulaSource
#   - InvokeFromPlanPath(): Runs a graph plan directly from a given path
#   - InvokeFromPlanPathOld(): Legacy path-based version for compatibility
#
# Behavior:
#   - All plans must resolve to an array of declarative GraphFormulaPlan objects
#   - All mutation is symbolic and sovereign (via Add-PathToDictionary)
#   - All results are signalized (wrapped in Result, Jacket, or Pointer)
#
# Outputs:
#   - Returns a Signal containing the resulting hydrated graph (or graphs)
#   - Logs and signal merges capture all transformation phases
#
# Use Case:
#   - Agent/Role/Adapter GSG construction
#   - Plan injection and execution via MappedCondenserAdapter
#   - Declarative runtime orchestration of multi-phase graph systems


class ConduitCondenser {
    [Conductor]$Conductor
    [MappedCondenserAdapter]$MappedCondenserAdapter
    [Signal]$Signal  # Sovereign control signal

    ConduitCondenser() {
        # Empty constructor, to enforce use of .Start()472
    }

    static [ConduitCondenser] Start([MappedCondenserAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [ConduitCondenser]::new()
        $instance.MappedCondenserAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("ConduitCondenser")
        return $instance
    }
    
    [Signal]Invoke([string]$Slot, [string]$Activity, [Signal]$ConductionSignal, [object]$Plan, [Signal]$ItemSignal) {
        $opSignal = [Signal]::Start("TransformCondenser.Invoke") | Select-Object -Last 1

        if ($Activity) {
            switch ($Activity) {

                # Process a Signal Graph's Grid 
                "Process" {
                    $opSignal = [Signal]::Start("GraphLauncher.Invoke", $ItemSignal) | Select-Object -Last 1
                    $SourcePathSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "ForEachPath" | Select-Object -Last 1
                    
                    if ($opSignal.MergeSignalAndVerifyFailure($SourcePathSignal)) {
                        return $opSignal
                    }

                    $sourceSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $SourcePathSignal.GetResult() | Select-Object -Last 1
                    $opSignal.MergeSignal($sourceSignal) | Out-Null

                    if ($opSignal.MergeSignalAndVerifyFailure($sourceSignal)) {
                        $opSignal.LogCritical("Failed to resolve FlatFormulaSource.")
                        return $opSignal
                    }

                    $clonePlan = (Resolve-ClonePlan -Plan $Plan | Select-Object -Last 1).GetResult()

                    $clonePlan.Adapter = $clonePlan.ForEachAdapter
                    $clonePlan.Activity = $clonePlan.ForEachActivity
                    
                    # Call our declarative plan processor
                    $resultSignal = Invoke-ProcessConduitCondenser -Signal $ConductionSignal -ItemSignal $sourceSignal -Plan $clonePlan | Select-Object -Last 1
                    $opSignal.MergeSignal($resultSignal) | Out-Null

                    if ($resultSignal.HasResult()) {
                        $opSignal.SetResult($resultSignal.GetResult())
                    }

                    break
                }

                # Converts a named object Array into a graph, or takes a graph and extends it with an array.  (Move to Graph Condenser and join with ConduitCondenser functionality like navigate grid?)
                "Graph" {
                    # Taken from Invoke-ConduitCondenser
                    $opSignal = [Signal]::Start("Invoke-ConduitCondenser", $ConductionSignal) | Select-Object -Last 1
                    $PlanName = $Plan.Name

                    if ($PlanName -eq "ConductionGraphPerRole") {
                        $opSignal.LogInformation("🔄 Executing Grid Condenser for plan: $($Plan.Name)")
                    }

                    $pathResultSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Path" | Select-Object -Last 1

                    $Path = $pathResultSignal.GetResult()
                    $segments = $Path -split '\.'
                    $selectResult = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $Path | Select-Object -Last 1
                    $graphName = $segments | Select-Object -Last 1

                    $subSignal = [Signal]::Start("GraphPlan:$PlanName", $ConductionSignal) | Select-Object -Last 1
                    $subSignal.SetJacket($selectResult) | Out-Null

                    $graphSignal = Resolve-GraphForJsonArray -ConductionSignal $ConductionSignal -Plan $Plan  -GraphName $graphName -ItemSignal $subSignal | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($graphSignal)) {
                        $opSignal.LogWarning("Failed to resolve graph for plan: $PlanName")
                        return $opSignal
                    }

                    # We leave the graph inside the resulting $opSignal because that's the reference for the Graph
                    $opSignal.SetResult($graphSignal)
                    $opSignal.LogInformation("✅ Graph plan '$PlanName' completed successfully.")
                    return $opSignal
                    break
                }

                default {
                    $opSignal.LogWarning("Unsupported Activity: $Activity")
                    break
                }
            }
        }

        return $opSignal
    }

}
