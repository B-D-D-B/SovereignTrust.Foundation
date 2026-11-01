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

<#
Class: MapCondenser
Purpose: Perform map condenser operations.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- Invoke: Invoke a mapped operation.
- Map: Map values into a target.
ActivityValidation: OnInvoke, BeforeDispatch
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
#>
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

        if ($Activity -notin @('Invoke', 'Map')) {
#            $opSignal.LogCritical("Unsupported MapCondenser activity: '$Activity'.")
#            return $opSignal
        }
        
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
                    $proposalSignal = $null
                    $data = $ItemSignal.GetResult()
                    if ($Plan -is $ItemSignal.GetType()) {
                        $proposalSignal = $Plan
                    }
                    else {
                        if ($null -eq $Plan) { return $opSignal.LogCritical('Map requires Config.ProposalPath or a Proposal Signal.') }
                        $proposalPathSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path 'Config.ProposalPath' -SignalLevel 'Warning' | Select-Object -Last 1
                        if ($proposalPathSignal.Failure() -or -not $proposalPathSignal.HasResult() -or [string]::IsNullOrWhiteSpace([string]$proposalPathSignal.GetResult())) {
                            return $opSignal.LogCritical('Map requires a nonempty Config.ProposalPath.')
                        }
                        $proposalAccessor = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path ([string]$proposalPathSignal.GetResult()) | Select-Object -Last 1
                        if ($proposalAccessor.Failure() -or -not $proposalAccessor.HasResult()) { return $opSignal.LogCritical('Map ProposalPath did not resolve.') }
                        $proposalSignal = $proposalAccessor.GetResult()
                        $dataPathSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path 'Config.DataPath' -Default $null -SignalLevel 'Warning' | Select-Object -Last 1
                        if ($dataPathSignal.HasResult()) {
                            $dataSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path ([string]$dataPathSignal.GetResult()) | Select-Object -Last 1
                            if ($dataSignal.Failure() -or -not $dataSignal.HasResult()) { return $opSignal.LogCritical('Map DataPath did not resolve.') }
                            $data = $dataSignal.GetResult()
                        }
                    }
                    if ($proposalSignal -isnot $ItemSignal.GetType() -or -not $proposalSignal.HasResult()) {
                        return $opSignal.LogCritical('Map proposal must be a Signal with a Result.')
                    }
                    $contentSignal = Resolve-PathFromDictionary -Dictionary $proposalSignal -Path '@.Content' -SignalLevel 'Warning' | Select-Object -Last 1
                    if ($contentSignal.Failure() -or -not $contentSignal.HasResult()) { return $opSignal.LogCritical('Map proposal Content is missing.') }
                    $modeSignal = Resolve-PathFromDictionary -Dictionary $proposalSignal -Path '@.CondenserMode' -Default 'Direct' -SignalLevel 'Warning' | Select-Object -Last 1
                    if ($modeSignal.Failure() -or $modeSignal.GetResult() -notin @('Direct','Template')) { return $opSignal.LogCritical('Map proposal CondenserMode is unsupported.') }
                    $dataProxy = [Signal]::Start('MapCondenser.DataProxy', $ItemSignal) | Select-Object -Last 1
                    $dataProxy.SetResult($data)
                    $Context = $ItemSignal
                    $resultSignal = Invoke-MapCondenser -Signal $dataProxy -ProposalSignal $proposalSignal -Context $Context | Select-Object -Last 1
                    if ($null -eq $resultSignal -or $opSignal.MergeSignalAndVerifyFailure($resultSignal)) { return $opSignal.LogCritical('Map proposal dispatch failed.') }
                    if ($resultSignal.HasResult()) { $opSignal.SetResult($resultSignal.GetResult()) }
                    
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

        if ($Plan -isnot $ItemSignal.GetType() -or -not $Plan.HasResult()) {
            return $opSignal.LogCritical('Map proposal must be a Signal with a Result.')
        }

        $resultSignal = Invoke-MapCondenser -Signal $ItemSignal -ProposalSignal $Plan -Context $Context | Select-Object -Last 1
        if ($null -eq $resultSignal -or $opSignal.MergeSignalAndVerifyFailure($resultSignal)) { return $opSignal.LogCritical('Map proposal dispatch failed.') }

        if ($resultSignal.HasResult()) {
            $opSignal.SetResult($resultSignal.GetResult())
        }

        return $opSignal
    }
}
