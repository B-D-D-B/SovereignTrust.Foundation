# =============================================================================
# 🚦 ConductionCondenser (SovereignTrust Declarative Command Processor)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom 🤖/☠️🌻🚀️ • Neural Alchemist ⚗️☣️🐲 • Last Generated: 05/20/2025
# =============================================================================
# The ConductionCondenser processes declarative ConductionPlans using signal-safe
# execution. Each Phase in the plan resolves a command template and executes it
# in context, emitting traceable signals at each step. This system replaces
# imperative scripts with sovereign lifecycle-encoded execution.

<#
Class: ConductionCondenser
Purpose: Perform conduction condenser operations.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- ST: Execute a SovereignTrust conduction plan.
- Sleep: Pause for Config.Duration seconds and report measured duration and tolerance match.
ActivityValidation: OnInvoke, BeforeDispatch
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
#>
class ConductionCondenser {
    hidden static [bool] DurationMatches([double]$ActualDuration, [double]$RequestedDuration) {
        return [math]::Abs($ActualDuration - $RequestedDuration) -le 0.1
    }

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

#        if ($Activity -notin @('ST')) {
#            $opSignal.LogCritical("Unsupported ConductionCondenser activity: '$Activity'.")
#            return $opSignal
#        }

        if ($Activity -eq 'Sleep') {
            $stopwatch = $null
            try {
                $durationValue = $Plan.Config.Duration
                if ($null -eq $durationValue) {
                    $opSignal.LogCritical('Plan.Config.Duration is required for Sleep.')
                    return $opSignal
                }

                $typeCode = [Type]::GetTypeCode($durationValue.GetType())
                if ($typeCode -notin @(
                    [TypeCode]::SByte, [TypeCode]::Byte,
                    [TypeCode]::Int16, [TypeCode]::UInt16,
                    [TypeCode]::Int32, [TypeCode]::UInt32,
                    [TypeCode]::Int64, [TypeCode]::UInt64,
                    [TypeCode]::Single, [TypeCode]::Double,
                    [TypeCode]::Decimal
                )) {
                    $opSignal.LogCritical('Plan.Config.Duration must be a finite, nonnegative number of seconds.')
                    return $opSignal
                }

                $duration = [double]$durationValue
                if ([double]::IsNaN($duration) -or [double]::IsInfinity($duration) -or $duration -lt 0) {
                    $opSignal.LogCritical('Plan.Config.Duration must be a finite, nonnegative number of seconds.')
                    return $opSignal
                }

                $stopwatch = [Diagnostics.Stopwatch]::StartNew()
                Start-Sleep -Seconds $duration -ErrorAction Stop
                $stopwatch.Stop()
                $actualDuration = $stopwatch.Elapsed.TotalSeconds
                $opSignal.SetResult([pscustomobject]@{
                    ActualDuration = $actualDuration
                    Matched = [ConductionCondenser]::DurationMatches($actualDuration, $duration)
                })
                return $opSignal
            }
            catch {
                if ($null -ne $stopwatch) { $stopwatch.Stop() }
                $opSignal.LogCritical("Sleep failed: $($_.Exception.Message)", $null, $_)
                return $opSignal
            }
        }

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
