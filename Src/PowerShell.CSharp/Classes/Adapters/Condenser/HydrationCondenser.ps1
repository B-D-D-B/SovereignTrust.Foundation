# =============================================================================
# 💧 HydrationCondenser (Context Import + Token Resolver)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☠️🧁👾️/🤖 • Neural Alchemist ⚗️☣️🐲 • Last Updated: 05/20/2025
# =============================================================================
# Condenser for resolving tokens, importing graph memory, and applying contextual
# substitutions from external XML-based token maps. Used in dynamic hydration
# flows during SDA Fusion execution and Conduction plan generation.
# =============================================================================

<#
Class: HydrationCondenser
Purpose: Perform hydration condenser operations.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- Invoke: Apply plan hydration to a signal.
ActivityValidation: OnInvoke, BeforeDispatch
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
#>
class HydrationCondenser {
    [SovereignTrust.Foundation.Classes.Conduction.Conductor]$Conductor
    [SovereignTrust.Foundation.Classes.Adapters.MappedCondenserAdapter]$MappedCondenserAdapter
    [SignalGraph.Signal]$Signal  # Formerly ControlSignal

    HydrationCondenser() {
        # Empty constructor — use Start() method instead.
    }

    static [HydrationCondenser] Start([SovereignTrust.Foundation.Classes.Adapters.MappedCondenserAdapter]$mappedAdapter, [SovereignTrust.Foundation.Classes.Conduction.Conductor]$conductor) {
        $instance = [HydrationCondenser]::new()
        $instance.MappedCondenserAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [SignalGraph.Signal]::Start("HydrationCondenser.Control") | Select-Object -Last 1
        return $instance
    }

    [SignalGraph.Signal]Invoke($Slot, $Activity, $Signal, $Plan, $ItemSignal) {
        $opSignal = [SignalGraph.Signal]::Start("HydrationCondenser.Invoke", $ItemSignal) | Select-Object -Last 1

        if ($Activity -notin @('Invoke')) {
            $opSignal.LogCritical("Unsupported HydrationCondenser activity: '$Activity'.")
            return $opSignal
        }

        # TODO: Review, do we want to clone $ItemSignal since hydration modifies in place?
        $resultSignal = Invoke-ApplyHydrationCondenser -Signal $Signal -Plan $Plan -ItemSignal $ItemSignal 
        $opSignal.SetResult($resultSignal.GetResult())
        return $opSignal
    }
}
