# =============================================================================
# 💧 HydrationCondenser (Context Import + Token Resolver)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☠️🧁👾️/🤖 • Neural Alchemist ⚗️☣️🐲 • Last Updated: 05/20/2025
# =============================================================================
# Condenser for resolving tokens, importing graph memory, and applying contextual
# substitutions from external XML-based token maps. Used in dynamic hydration
# flows during SDA Fusion execution and Conduction plan generation.
# =============================================================================

class HydrationCondenser {
    [Conductor]$Conductor
    [MappedCondenserAdapter]$MappedCondenserAdapter
    [Signal]$Signal  # Formerly ControlSignal

    HydrationCondenser() {
        # Empty constructor — use Start() method instead.
    }

    static [HydrationCondenser] Start([MappedCondenserAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [HydrationCondenser]::new()
        $instance.MappedCondenserAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("HydrationCondenser.Control") | Select-Object -Last 1
        return $instance
    }

    [Signal]Invoke($Slot, $Activity, $Signal, $Plan, $ItemSignal) {
        $opSignal = [Signal]::Start("HydrationCondenser.Invoke", $ItemSignal) | Select-Object -Last 1

        # TODO: Review, do we want to clone $ItemSignal since hydration modifies in place?
        $resultSignal = Invoke-ApplyHydrationCondenser -Signal $Signal -Plan $Plan -ItemSignal $ItemSignal 
        $opSignal.SetResult($resultSignal.GetResult())
        return $opSignal
    }
}
