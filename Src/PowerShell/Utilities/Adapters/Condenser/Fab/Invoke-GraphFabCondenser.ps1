# =============================================================================
# 📍 Invoke-GraphFabCondenser (Declarative Graph Builder + Injector)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists / BDDB
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

function Invoke-GraphFabCondenser {
    param (
        [Signal]$Signal,
        [object]$Plan,
        [object]$ItemSignal,
        [string]$PlanWirePathPrefix = "%.%.%.@"  # <- new param with default
    )

    $opSignal = [Signal]::Start("Invoke-GraphFabCondenser:$Plan.Name", $Signal) | Select-Object -Last 1

    $PlanName = $Plan.Name
  #  $subSignal = [Signal]::Start("GraphPlan:$PlanName", $Signal) | Select-Object -Last 1
  #  $subSignal.SetJacket($ItemSignal) | Out-Null

    
    $JacketSignalWrapper = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%" | Select-Object -Last 1
    $JacketSignal = $JacketSignalWrapper.GetResult()
    $conductorJacketSignal = Resolve-PathFromDictionary -Dictionary $Signal -Path "%" | Select-Object -Last 1
    $loadingModeSignal = Resolve-PathFromDictionary `
        -Dictionary $Plan `
        -Path 'Config.AdapterLoading.Mode' `
        -Default 'Lazy' `
        -SignalLevel 'Information' `
    | Select-Object -Last 1
    $retrySignal = Resolve-PathFromDictionary `
        -Dictionary $Plan `
        -Path 'Config.AdapterLoading.RetryFailedResolution' `
        -Default $false `
        -SignalLevel 'Information' `
    | Select-Object -Last 1

    if ([string]$loadingModeSignal.GetResult() -ne 'Eager') {
        $addSignal = Register-AdapterToMappedSlot `
            -ConductorJacketSignal $conductorJacketSignal.GetResult() `
            -Signal $Signal `
            -ConductionContext $Signal `
            -Adapter $JacketSignal `
            -Lazy `
            -RetryFailedResolution ([bool]$retrySignal.GetResult()) `
        | Select-Object -Last 1
    }
    else {
        $resolveAdapterSignal = Resolve-AdapterFromJacket `
            -Signal $Signal `
            -ConductionContext $Signal `
            -Jacket $JacketSignal `
        | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($resolveAdapterSignal) -or -not $resolveAdapterSignal.HasResult()) {
            return $opSignal
        }

        $addSignal = Register-AdapterToMappedSlot `
            -ConductorJacketSignal $conductorJacketSignal.GetResult() `
            -Signal $Signal `
            -ConductionContext $Signal `
            -Adapter $resolveAdapterSignal `
        | Select-Object -Last 1
    }

    if ($opSignal.MergeSignalAndVerifyFailure($addSignal)) {
        $opSignal.LogCritical("❌ Failed to add adapter to appropriate Mapped Adapter.")
        return $opSignal
    }

    if ($Plan.TargetWirePath) {
        $injectSignal = Add-PathToDictionary -Dictionary $ItemSignal -Path $Plan.TargetWirePath -Value $addSignal.GetResult() | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($injectSignal)) {
            $opSignal.LogCritical("❌ Failed to inject graph into '$($Plan.TargetWirePath)'")
            return $opSignal
        }
        $opSignal.LogInformation("📍 Injected graph '$PlanName' into '$($Plan.TargetWirePath)'")
    }

    <# Done in Register-AdapterToMappedSlot
    $isMappedSignal = Resolve-PathFromDictionary -Dictionary $JacketSignal -Path "@.IsMapped" | Select-Object -Last 1
    if ($opSignal.MergeSignalAndVerifyFailure($isMappedSignal)) {
        $opSignal.LogRecovery("IsMapped status for jacket Not Required, Assumed False.")
    }
    else {
        $isMapped = $isMappedSignal.GetResult()
        if ($isMapped -eq $true) {
            $adapterKindSignal = Resolve-PathFromDictionary -Dictionary $Adapter -Path "%.Kind" | Select-Object -Last 1
            $adapterKind = $adapterKindSignal.GetResult()
            $adapterSlotSignal = Resolve-PathFromDictionary -Dictionary $Adapter -Path "%.Slot" | Select-Object -Last 1
            $adapterSlot = $adapterSlotSignal.GetResult()
            $mappedAdapterSignal = Resolve-PathFromDictionary -Dictionary $Signal -Path "%.*.#.Adapters.*.#.Mapped$($adapterKind)" | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure($mappedAdapterSignal)) {
                $opSignal.LogWarning("Failed to resolve mapped adapter for '$PlanName'.")
            }
            else {
                $mappedAdapter = $mappedAdapterSignal.GetResult()
                while ($mappedAdapter -is [Signal]) {
                    $mappedAdapter = $mappedAdapter.GetResult()
                }

                $registerSignal = $mappedAdapter.RegisterAdapter($ResolveAdapterSignal, $adapterSlot) | Select-Object -Last 1
                if ($opSignal.MergeSignalAndVerifyFailure($registerSignal)) {
                    $opSignal.LogCritical("❌ Failed to register mapped adapter '$PlanName' in slot '$adapterSlot'.")
                    return $opSignal
                }
                
                $opSignal.LogInformation("✅ Mapped adapter '$PlanName' successfully.")

                $opSignal.SetResult($ResolveAdapterSignal)
            }
        }
    }
    #>
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

    $opSignal.LogInformation("✅ Graph Fab plan '$PlanName' completed successfully.")
    return $opSignal
}
