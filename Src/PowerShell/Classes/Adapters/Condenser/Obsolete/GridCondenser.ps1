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


class GridCondenser {
    [Conductor]$Conductor
    [MappedCondenserAdapter]$MappedCondenserAdapter
    [Signal]$Signal  # Sovereign control signal

    GridCondenser() {
        # Empty constructor, to enforce use of .Start()472
    }

    static [GridCondenser] Start([MappedCondenserAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [GridCondenser]::new()
        $instance.MappedCondenserAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("GridCondenser")
        return $instance
    }
    
    [Signal]Invoke([string]$Slot, [string]$Activity, [Signal]$ConductionSignal, [object]$Plan, [Signal]$ItemSignal) {
        $opSignal = [Signal]::Start("TransformCondenser.Invoke") | Select-Object -Last 1

        if ($Activity) {
            switch ($Activity) {

                # Process a Signal Graph's Grid 
                "Process" {
                    $opSignal = [Signal]::Start("GraphLauncher.Invoke", $this.Signal) | Select-Object -Last 1
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
                    
                    $clonePlan.SourceAdapter = $clonePlan.ForEachSourceAdapter
                    $clonePlan.SourceActivity = $clonePlan.ForEachSourceActivity
                    
                    # Call our declarative plan processor
                    $resultSignal = Invoke-ProcessGridCondenser -Signal $ConductionSignal -ItemSignal $sourceSignal -Plan $clonePlan | Select-Object -Last 1
                    $opSignal.MergeSignal($resultSignal) | Out-Null

                    if ($resultSignal.HasResult()) {
                        $opSignal.SetResult($resultSignal.GetResult())
                    }

                    break
                }

                # Converts a named object Array into a graph, or takes a graph and extends it with an array.  (Move to Graph Condenser and join with GridCondenser functionality like navigate grid?)
                "Graph" {
                    # Taken from Invoke-GridCondenser
                    $opSignal = [Signal]::Start("Invoke-GridCondenser", $ConductionSignal) | Select-Object -Last 1
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


    [Signal] Invoke([string]$Path, [object]$Plan) {
        $opSignal = [Signal]::Start("GraphLauncher.Invoke", $this.
            Signal) | Select-Object -Last 1

        $sourceSignal = Resolve-PathFromDictionary -Dictionary $this.Conductor -Path "%.FlatFormulaSource" | Select-Object -Last 1
        $opSignal.MergeSignal($sourceSignal) | Out-Null

        if ($opSignal.MergeSignalAndVerifyFailure($sourceSignal)) {
            $opSignal.LogCritical("Failed to resolve FlatFormulaSource.")
            return $opSignal
        }

        $sourceData = $sourceSignal.GetResult()

        # Construct signal to feed into the GraphCondenser
        $feedSignal = [Signal]::Start("GridCondenser.Feed", $opSignal, $null, $sourceData) | Select-Object -Last 1
        Add-PathToDictionary -Dictionary $feedSignal -Path "$.%.GraphPlans" -Value $sourceData.GraphPlans | Out-Null

        # Call our declarative plan processor
        $resultSignal = Invoke-GraphCondenser -ConductionSignal $feedSignal | Select-Object -Last 1
        $opSignal.MergeSignal($resultSignal) | Out-Null

        $opSignal.SetResult($resultSignal.GetResult())
        return $opSignal
    }

    [Signal] InvokeFromPlanPath([string]$PlanWirePath, [object]$jacketObject) {
        $opSignal = [Signal]::Start("GridCondenser.InvokeFromPlanPath") | Select-Object -Last 1

        # Determine base memory to evolve (from existing Result or jacket)
        $initialMemory = if ($this.Signal -and $this.Signal.HasResult()) {
            $this.Signal.GetResult()
        }
        else {
            $jacketObject
        }

        # Start a new signal for Condenser with memory + jacket
        $condenserSignal = [Signal]::Start("GridCondenser", $jacketObject) | Select-Object -Last 1
        $condenserSignal.SetJacket($jacketObject) | Out-Null

        # Extract graph plans using WirePath
        $planSignal = Resolve-PathFromDictionary -Dictionary $condenserSignal -Path $PlanWirePath | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($planSignal)) {
            $opSignal.LogCritical("Failed to resolve GraphPlans from path: $PlanWirePath")
            return $opSignal
        }

        # Inject plans into %.GraphPlans for downstream Condenser
        $graphPlans = $planSignal.GetResult()
        Add-PathToDictionary -Dictionary $condenserSignal -Path "%.%.%.@.GraphPlans" -Value $graphPlans | Out-Null

        # 🔁 Invoke the GraphCondenser
        $resultSignal = Invoke-GridCondenser -Signal $condenserSignal | Select-Object -Last 1

        # Merge final state back to opSignal for continuity
        $opSignal.SetResult($resultSignal.GetResult())
        $opSignal.MergeSignal($resultSignal)

        return $opSignal
    }
}
