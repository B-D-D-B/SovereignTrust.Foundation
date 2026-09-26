# =============================================================================
# 🧩 MapCondenser (Symbolic Mapping + Contextual Replacement)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☠️🧁👾️/🤖 • Neural Alchemist ⚗️☣️🐲 • Last Updated: 07/12/2025
# =============================================================================
# Performs template condensation using dynamic mappings and embedded context.
# Resolves tags such as `@@TAG`, `##TAG`, `<TAG />` using sovereign source maps.
# Often used in Condenser chains during token hydration, agent bootstrap, or
# reactive publishing from flattened Plan schemas.
# =============================================================================

class MapCondenser {
    [Conductor]$Conductor
    [MappedCondenserAdapter]$MappedCondenserAdapter
    [Signal]$Signal  # Previously ControlSignal

    MapCondenser() {
        # Empty constructor — use .Start()
    }
       
    static [MapCondenser] Start([MappedCondenserAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [MapCondenser]::new()
        $instance.MappedCondenserAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("MapCondenser.Start") | Select-Object -Last 1
        return $instance
    }

    [Signal] Invoke([string]$Slot, [string]$Activity, $ConductionSignal, $Plan, $ItemSignal) {
        # For the Content Condenser, the plan contains the steps to perform, similar to the steps in the FormulaGraphCondenser but 2 dimensional mappings

        $opSignal = [Signal]::Start("MapCondenser.Invoke", $ItemSignal) | Select-Object -Last 1
        
        # First Supported Activities -> Select, Merge, Project
        $DefaultPath = "%.@"
        if ($Activity) {
            switch ($Activity) {

                # Converts a named object Array into a graph, or takes a graph and extends it with an array.  (Move to Graph Condenser and join with GridCondenser functionality like navigate grid?)
                #"Direct" - this is Invoke below instead of something declarative because it's coming through the hydration condenser and we aren't changing that in this revision set.
                "Invoke" {

                    ## Require Result or Jacket to have value.
                    #$result = $ItemSignal.HasResult() ? $ItemSignal.GetResult() : $ItemSignal.GetJacket().GetResult()
                    $sourceContentPathSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Path" | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($sourceContentPathSignal)) { 
                        return $opSignal }

                    $resultSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $sourceContentPathSignal.GetResult() | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)) { 
                        return $opSignal }

                    $result = $resultSignal.GetResult()

                    # Fix this, we should not be mutating ItemSignal, we should create the proxy and pass the result through.
                    $ItemProxySignal = $ItemSignal

                    if ($result -is [string]) {
                        $resultObject = [pscustomobject]@{
                            Message = $result
                        }
                        # Generate a new object to act as the Signle to pass in as a proxy
                         $null = Add-PathToDictionary -Dictionary $ItemSignal -Path $sourceContentPathSignal.GetResult() -Value $resultObject

                    }

                    $condenserResult = Invoke-JsonTokenCondenser -Signal $ConductionSignal -ItemSignal $ItemSignal -Plan $Plan | Select-Object -Last 1

                    if ($result -is [string]) {
                        $messageObject = $condenserResult.GetResult()
                        $opSignal.SetResult($messageObject.Message);
                    }
                    else {
                        $opSignal.SetResult($condenserResult.GetResult());
                    }

                    $null = Add-PathToDictionary -Dictionary $ItemSignal -Path $sourceContentPathSignal.GetResult() -Value $opSignal.GetResult() | Select-Object -Last 1
                    break
                }

                "Map" {

                    if ($null -eq $Plan) {
                        $PlanSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%.@.Plan" | Select-Object -Last 1
                        $Plan = $PlanSignal.GetResult()
                    }

                    <#
                    if ($null -eq $Context) {
                        $ContextSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%.@.Context" | Select-Object -Last 1
                        $Context = $ContextSignal.GetResult()
                    }
                        #>
                    # HACKED TOGETHER TO MAKE WORK FROM BELOW, NOT CURRENTLY FUNCTIONAL
                        $Context = $ItemSignal
                    $resultSignal = Invoke-MapCondenser -Signal $ItemSignal -ProposalSignal $Plan -Context $Context | Select-Object -Last 1
                    $opSignal.MergeSignal($resultSignal)

                    if ($resultSignal.HasResult()) {
                        $opSignal.SetResult($resultSignal.GetResult())
                    }
                    
                    break
                }

                default {
                    $opSignal.LogWarning("Unsupported Activity: $Activity")
                    break
                }
            }

            return $opSignal
        }
        
        $returnItemSignalSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "ReturnItemSignal" -Default $false | Select-Object -Last 1
        if ($returnItemSignalSignal.GetResult()) {
            $opSignal.SetResult($ItemSignal)
        }

        return $opSignal

    }

    [Signal] Invoke([Signal]$ItemSignal, [object]$Plan, [object]$Context = $null) {
        $opSignal = [Signal]::Start("MapCondenser.Invoke", $ItemSignal) | Select-Object -Last 1

        if ($null -eq $Plan) {
            $PlanSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%.@.Plan" | Select-Object -Last 1
            $Plan = $PlanSignal.GetResult()
        }

        if ($null -eq $Context) {
            $ContextSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%.@.Context" | Select-Object -Last 1
            $Context = $ContextSignal.GetResult()
        }

        $resultSignal = Invoke-MapCondenser -Signal $ItemSignal -ProposalSignal $Plan -Context $Context | Select-Object -Last 1
        $opSignal.MergeSignal($resultSignal)

        if ($resultSignal.HasResult()) {
            $opSignal.SetResult($resultSignal.GetResult())
        }

        return $opSignal
    }
}
