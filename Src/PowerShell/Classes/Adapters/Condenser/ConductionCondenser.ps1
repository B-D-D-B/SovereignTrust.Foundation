# =============================================================================
# 🚦 ConductionCondenser (SovereignTrust Declarative Command Processor)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom 🤖/☠️🌻🚀️ • Neural Alchemist ⚗️☣️🐲 • Last Generated: 05/20/2025
# =============================================================================
# The ConductionCondenser processes declarative ConductionPlans using signal-safe
# execution. Each Phase in the plan resolves a command template and executes it
# in context, emitting traceable signals at each step. This system replaces
# imperative scripts with sovereign lifecycle-encoded execution.

class ConductionCondenser {
    [Conductor]$Conductor
    [MappedCondenserAdapter]$MappedCondenserAdapter
    [Signal]$Signal  # Previously ControlSignal

    ConductionCondenser() {
        # Empty constructor — use .Start()
    }
       
    static [ConductionCondenser] Start([MappedCondenserAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [ConductionCondenser]::new()
        $instance.MappedCondenserAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("ConductionCondenser.Control") | Select-Object -Last 1
        return $instance
    }

    
    [Signal]Invoke([string]$Slot, [string]$Activity, [Signal]$ConductionSignal, [object]$Plan, [Signal]$ItemSignal) {

        # For the Content Condenser, the plan contains the steps to perform, similar to the steps in the FormulaGraphCondenser but 2 dimensional mappings

        $opSignal = [Signal]::Start("ConductionCondenser.Invoke", $ItemSignal) | Select-Object -Last 1

        $resultSignal = Invoke-MappedAdapter -Signal $ConductionSignal -ItemSignal $ItemSignal -Plan $Plan -Adapter "Conduction.$Activity" -Activity $Activity  | Select-Object -Last 1

        <# Old Way
        $AdapterPath = "*.#.$Activity"
        $adapterSignal = Resolve-PathFromDictionary -Dictionary $this.Signal -Path $AdapterPath | Select-Object -Last 1

        $adapter = $adapterSignal.GetResult($true)
        $resultSignal = $adapter.Invoke($Slot, $Activity, $ConductionSignal, $Plan, $ItemSignal)
#>
        if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)) {

                    $resultSignal = Invoke-MappedAdapter -Signal $ConductionSignal -ItemSignal $ItemSignal -Plan $Plan -Adapter "Conduction.$Activity" -Activity $Activity  | Select-Object -Last 1

            $opSignal.LogCritical("MappedStorageAdapter failed to invoke against slot '$Slot'.")
            return $opSignal
        }

        $opSignal.SetResult($resultSignal.GetResult())


        return $opSignal
    }

    [Signal] Invoke([object]$Context) {
        return $this.Invoke($Context, $null) | Select-Object -Last 1
    }

    [Signal] Invoke([object]$Context, [object]$Plan) {
        return Invoke-ConductionCondenser -ConductionSignal $Context | Select-Object -Last 1
    }
}
