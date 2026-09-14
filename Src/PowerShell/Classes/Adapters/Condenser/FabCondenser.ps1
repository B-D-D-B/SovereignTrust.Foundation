# =============================================================================
# 🧩 FabCondenser (Symbolic Mapping + Contextual Replacement)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists / BDDB
#  Authors: Shadow PhanTom ☠️🧁👾️/🤖 • Neural Alchemist ⚗️☣️🐲 • Last Updated: 07/12/2025
# =============================================================================
# Performs template condensation using dynamic mappings and embedded context.
# Resolves tags such as `@@TAG`, `##TAG`, `<TAG />` using sovereign source maps.
# Often used in Condenser chains during token hydration, agent bootstrap, or
# reactive publishing from flattened proposal schemas.
# =============================================================================

class FabCondenser {
    [Conductor]$Conductor
    [MappedCondenserAdapter]$MappedCondenserAdapter
    [Signal]$Signal  # Previously ControlSignal

    FabCondenser() {
        # Empty constructor — use .Start()
    }
       
    static [FabCondenser] Start([MappedCondenserAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [FabCondenser]::new()
        $instance.MappedCondenserAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("FabCondenser.Control") | Select-Object -Last 1
        return $instance
    }

    [Signal]Invoke($Slot, $Activity, $Signal, $Plan, $ItemSignal) {
        $opSignal = [Signal]::Start("FabCondenser.Invoke", $ItemSignal) | Select-Object -Last 1

        $JacketSignalWrapper = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%" | Select-Object -Last 1
        $JacketSignal = $JacketSignalWrapper.GetResult()
        $ResolveAdapterSignal = Resolve-AdapterFromJacket -Signal $Signal -ConductionContext $Signal -Jacket $JacketSignal | Select-Object -Last 1

        $Adapter = $ResolveAdapterSignal.GetResult() | Select-Object -Last 1

        $opSignal.SetResult($Adapter)

#        $VirtualPathSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%.@.VirtualPath" | Select-Object -Last 1
#        $VirtualPath = $VirtualPathSignal.GetResult()
#        Write-Host "ResolveAdapterSignal $VirtualPath"

        $addSignal = Register-AdapterToMappedSlot -ConductorJacketSignal $Signal.GetJacket() -Adapter $ResolveAdapterSignal | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure($addSignal)) {
            $opSignal.LogCritical("Failed to add adapter to appropriate Mapped Adapter.")
            return $opSignal
        }

        return $opSignal
    }

    [Signal] InvokeOld([Signal]$ItemSignal, [object]$Proposal, [object]$Context = $null) {
        $opSignal = [Signal]::Start("FabCondenser.Invoke", $ItemSignal) | Select-Object -Last 1

        if ($null -eq $Proposal) {
            $ProposalSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%.Proposal" | Select-Object -Last 1
            $Proposal = $ProposalSignal.GetResult()
        }

        if ($null -eq $Context) {
            $ContextSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%.Context" | Select-Object -Last 1
            $Context = $ContextSignal.GetResult()
        }

        # TODO: Invoke-FabricateAdapter should be split into Invoke-FabricateAdapter and Invoke-AttachFabricatedAdapter
        $resultSignal = Invoke-FabricateAdapter -Signal $ItemSignal -Proposal $Proposal -Context $Context | Select-Object -Last 1
        $opSignal.MergeSignal($resultSignal)

        if ($resultSignal.HasResult()) {
            $opSignal.SetResult($resultSignal.GetResult())
        }

        return $opSignal
    }
}
