# =============================================================================
# 🧠 SDA MemoryCondenser
#  SovereignTrust Memory Interface for performing Invoke-MemoryCondenser calls
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists / BDDB
#  Authors: Shadow PhanTom 🤖/☠️🧁👾️ • Neural Alchemist ⚗️☣️🐲 • Version: 2025.5.4.8
# =============================================================================

class MemoryCondenser {
    [Signal]$Signal

    MemoryCondenser() {}

    static [Signal] Start([MappedCondenserAdapter]$adapter, [Conductor]$conductor) {
        $opSignal = [Signal]::Start("MemoryCondenser.Start") | Select-Object -Last 1

        $instance = [MemoryCondenser]::new()
        $instance.Signal = [Signal]::Start("MemoryCondenser", $adapter) | Select-Object -Last 1
        $instance.Signal.SetJacket($conductor) | Out-Null

        $opSignal.SetResult($instance)
        $opSignal.LogInformation("✅ MemoryCondenser initialized.")
        return $opSignal
    }

    [Signal]Invoke([string]$Slot, [string]$Activity, [Signal]$ConductionSignal, [object]$Plan, [Signal]$ItemSignal) {

        # For the Content Condenser, the plan contains the steps to perform, similar to the steps in the FormulaGraphCondenser but 2 dimensional mappings

        $opSignal = [Signal]::Start("MemoryCondenser.Invoke", $ItemSignal) | Select-Object -Last 1
        
        # First Supported Activities -> Select, Merge, Project
        if ($Activity) {
            switch ($Activity) {

                # Converts a named object Array into a graph, or takes a graph and extends it with an array.  (Move to Graph Condenser and join with GridCondenser functionality like navigate grid?)
                "Persist" {
                    break
                }

                "Generate" {
                    ###n/a# $Plan May be the container with the source details or it may be in a mappings collection

                    # TODO: Change to the DependsOn model like phases use
                    if (-not $ItemSignal.HasPointer()) {
                        $ItemSignal.CreateGraph()
                    }

                    $step = $this.GetNextStep($null, $Plan, $ItemSignal, $ConductionSignal)
                    while ($step) {
                        $breakSignal = Resolve-PathFromDictionary -Dictionary $step -Path "Config.Break" -Default $false | Select-Object -Last 1
                        if ($breakSignal.GetResult()) {
                            $Check = ""
                        }


                        $StepResultSignal = $null

                        # The Deferred Hydration Plan is used to hydrate the step, usually because a previous set puts content in memory or cache.
                        $DeferredHydrationPlanSignal = Resolve-PathFromDictionary -Dictionary $step -Path "DeferredHydrationPlan" -Default $null | Select-Object -Last 1
                        if ($DeferredHydrationPlanSignal.HasResult()) {
                            $HydrationSignal = [Signal]::Start("MemoryCondenser.Invoke.DeferredHydrate", $step) | Select-Object -Last 1
                            $HydrationSignal.SetJacket($StepResultSignal)

                            # Set the Step as   the result content of the jacket which is what is going to be hydrated.
                            $HydrationSignal.SetJacketResult($step)
                            $HydrationSignal.SetPointer($ItemSignal.GetPointer())

                            $HydrationPlan = [PSCustomObject]@{
                                Path           = "%.@"
                                HydrationStyle = "Deferred"
                                HydrationPlan  = $DeferredHydrationPlanSignal.GetResult()
                                Config         = $step.Config
                            }

                            # Perform Hydration
                            $StepHydrateResultSignal = Invoke-CondenserAdapter -Slot "Hydration" -Plan $HydrationPlan -Signal $ConductionSignal -ItemSignal $HydrationSignal | Select-Object -Last 1
                            if ($opSignal.MergeSignalAndVerifyFailure($StepHydrateResultSignal)) { return $opSignal }
                            $step = $StepHydrateResultSignal.GetResult()
                        }

                        $IsEnabledSignal = Resolve-PathFromDictionary -Dictionary $step -Path "IsEnabled" -Default $true | Select-Object -Last 1
                        if ($opSignal.MergeSignalAndVerifyFailure($IsEnabledSignal)) { return $opSignal }

                        $isEnabledResult = $IsEnabledSignal.GetResult()

                        if (-not $this.TestAllTrue($isEnabledResult)) {
                            $step = $this.GetNextStep($step, $Plan, $ItemSignal, $ConductionSignal) 
                            continue
                        }

                        $null = Add-PathToDictionary -Dictionary $step -Path "Phase" -Value $Plan

                        # Load the environment from Content storage and merge with passed in Environment *.#.Adapters
                        $PathSignal = Resolve-PathFromDictionary -Dictionary $step -Path "Path" -SignalLevel "Warning" | Select-Object -Last 1
                        $ResourceSignal = Resolve-PathFromDictionary -Dictionary $step -Path "Resource" -SignalLevel "Warning" | Select-Object -Last 1
                        $ContainerSignal = Resolve-PathFromDictionary -Dictionary $step -Path "Container" -SignalLevel "Warning" | Select-Object -Last 1
                        $FormatSignal = Resolve-PathFromDictionary -Dictionary $step -Path "Format" -SignalLevel "Warning" | Select-Object -Last 1
                        $ContentFormatSignal = Resolve-PathFromDictionary -Dictionary $step -Path "ContentFormat" -SignalLevel "Information" | Select-Object -Last 1
                        $ModeSignal = Resolve-PathFromDictionary -Dictionary $step -Path "Mode" -Default "Select" -SignalLevel "Information" | Select-Object -Last 1
                        $ActivitySignal = Resolve-PathFromDictionary -Dictionary $step -Path "Activity" -SignalLevel "Warning" | Select-Object -Last 1
                        $TypeSignal = Resolve-PathFromDictionary -Dictionary $step -Path "Type" -Default "Transform" | Select-Object -Last 1
                        $HydrationPlanSignal = Resolve-PathFromDictionary -Dictionary $step -Path "HydrationPlan" -Default $null | Select-Object -Last 1
                        $KeySignal = Resolve-PathFromDictionary -Dictionary $step -Path "Key" -Default $null | Select-Object -Last 1
                        $ExitAfterAdapterSignal = Resolve-PathFromDictionary -Dictionary $step -Path "ExitAfterAdapter" -Default $false | Select-Object -Last 1
                        $ExitAfterAdapterNoResult = Resolve-PathFromDictionary -Dictionary $step -Path "ExitAfterAdapterNoResult" -Default $false | Select-Object -Last 1

                        $Key = $KeySignal.HasResult() ? $KeySignal.GetResult() : $null
                        $Path = $PathSignal.HasResult()     ? $PathSignal.GetResult()     : $null
                        $Format = $FormatSignal.HasResult()    ? $FormatSignal.GetResult()    : $null
                        $ContentFormat = $ContentFormatSignal.HasResult()    ? $ContentFormatSignal.GetResult()    : $null

                        $AdapterSignal = Resolve-PathFromDictionary -Dictionary $step -Path "Adapter" -SignalLevel "Warning"  | Select-Object -Last 1

                        if ($AdapterSignal.HasResult()) {
                            #                            $Container = $ContainerSignal.HasResult() ? $ContainerSignal.GetResult() : $null
                            #                           $Resource = $ResourceSignal.HasResult() ? $ResourceSignal.GetResult() : $null

                            $StepResultSignal = Invoke-MappedAdapter `
                                -Signal $ConductionSignal `
                                -Adapter $AdapterSignal.GetResult() `
                                -Activity $ActivitySignal.GetResult() `
                                -Plan $step `
                                -ItemSignal $ItemSignal #`
                            #-Name $Resource
                            #                                -Container $Container `
                            | Select-Object -Last 1

                            if ($opSignal.MergeSignalAndVerifyFailure($StepResultSignal)) { return $opSignal }
                            $this.RegisterSignal($ItemSignal, $Key, $StepResultSignal)
                        }
                        else {
                            $StepResultSignal = [Signal]::Start("MemoryCondenser.EmptyStepResult") | Select-Object -Last 1
                        }

                        if (-not $StepResultSignal.HasResult() -and $ExitAfterAdapterNoResult.GetResult() ) {
                            return $opSignal
                        }

                        if ($StepResultSignal.HasResult() -and (-not $ExitAfterAdapterSignal.GetResult())) {

                            # Apply Hydration Steps

                            # Perform Document formatting, xml, json or leave txt
                            if ($Format) {
                                $FormatSignal = [Signal]::Start("MemoryCondenser.Invoke.Format", $ItemSignal) | Select-Object -Last 1
                                $FormatSignal.SetJacket($StepResultSignal)
                                $FormatSignal.SetPointer($ItemSignal.GetPointer())

                                $StepResultSignal = Invoke-CondenserAdapter -Slot "Format" -Activity $Format -Plan $step -Signal $ConductionSignal -ItemSignal $FormatSignal | Select-Object -Last 1
                                if ($opSignal.MergeSignalAndVerifyFailure($StepResultSignal)) { return $opSignal }
                                $this.RegisterSignal($ItemSignal, $Key, $StepResultSignal)
                            }

                            # Optional Condenser-Based Transform Step
                            # Currently uses a CondenserAdapter and then uses the SourceType in the mapping to determine which one to use and SourceMode to determine which activity to run.
                            if ($Path) {
                                $TransformSignal = [Signal]::Start("MemoryCondenser.Invoke.Transform", $ItemSignal) | Select-Object -Last 1
                                $TransformSignal.SetJacket($StepResultSignal)
                                $TransformSignal.SetPointer($ItemSignal.GetPointer())

                                $StepResultSignal = Invoke-CondenserAdapter -Slot $TypeSignal.GetResult() -Activity $ModeSignal.GetResult() -Plan $step -Signal $ConductionSignal -ItemSignal $TransformSignal | Select-Object -Last 1
                                if (-not $StepResultSignal.HasResult()) {
                                    # TODO: Move to inside condenser.
                                    $StepResultSignal.LogCritical("Path Not Found: $($Path) in $($ContainerSignal.GetResult())/$($ResourceSignal.GetResult())")
                                }
                                if ($opSignal.MergeSignalAndVerifyFailure($StepResultSignal)) { return $opSignal }
                                $this.RegisterSignal($ItemSignal, $Key, $StepResultSignal)
                            }

                            # Optional Hydration Condenser Step
                            if ($HydrationPlanSignal.HasResult()) {
                                $HydrationSignal = [Signal]::Start("MemoryCondenser.Invoke.Hydrate", $ItemSignal) | Select-Object -Last 1
                                $HydrationSignal.SetJacket($StepResultSignal)
                                $HydrationSignal.SetPointer($ItemSignal.GetPointer())

                                # Re-use the step in case hydration needs to come from
                                $HydrationPlan = (Resolve-ClonePlan -Plan $step | Select-Object -Last 1).GetResult()
                                
                                $null = Add-PathToDictionary -Dictionary $HydrationPlan -Path "HydrationPlan" -Value $HydrationPlanSignal.GetResult()
                                $null = Add-PathToDictionary -Dictionary $HydrationPlan -Path "Path" -Value "%.@"

                                # Perform Hydration
                                $StepResultSignal = Invoke-CondenserAdapter -Slot "Hydration" -Plan $HydrationPlan -Signal $ConductionSignal -ItemSignal $HydrationSignal | Select-Object -Last 1
                                if ($opSignal.MergeSignalAndVerifyFailure($StepResultSignal)) { return $opSignal }
                                $this.RegisterSignal($ItemSignal, $Key, $StepResultSignal)
                            }
                
                            if ($ContentFormat) {
                                $ContentFormatSignal = [Signal]::Start("MemoryCondenser.Invoke.ContentFormat", $ItemSignal) | Select-Object -Last 1
                                $ContentFormatSignal.SetJacket($StepResultSignal)
                                $ContentFormatSignal.SetPointer($ItemSignal.GetPointer())

                                $FormatPlan = [PSCustomObject]@{
                                    Format = $ContentFormat
                                }

                                $StepResultSignal = Invoke-CondenserAdapter -Slot "Format" -Activity $ContentFormat -Plan $FormatPlan -Signal $ConductionSignal -ItemSignal $ContentFormatSignal | Select-Object -Last 1
                                if ($opSignal.MergeSignalAndVerifyFailure($StepResultSignal)) { return $opSignal }
                                $this.RegisterSignal($ItemSignal, $Key, $StepResultSignal)
                            }
                        }

                        $step = $this.GetNextStep($step, $Plan, $ItemSignal, $ConductionSignal)
                    }
                    break
                }

                default {
                    $opSignal.LogWarning("Unsupported Activity: $Activity")
                    break
                }
            }
        }
        
        $returnItemSignalSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "ReturnItemSignal" -Default $false | Select-Object -Last 1
        if ($returnItemSignalSignal.GetResult()) {
            $opSignal.SetResult($ItemSignal)
        }

        return $opSignal
    }

    [object] GetNextStep(
        [object]$currentStep,
        [object]$phase,
        [Signal]$ItemSignal,
        [Signal]$ConductionSignal
    ) {
        $step = $null
        
        if ($phase.Steps) {
            $phaseSteps = @($phase.Steps)

#            foreach ($phaseStep in $phaseSteps) {
#                if (-not $phaseStep.Name) {
#                    $null = Add-PathToDictionary -Dictionary $phaseStep -Path "Name" -Value  New-Guid
#                }
#            }

            # If no current step, return the first step (if any)
            if (-not $currentStep) {
                if ($phaseSteps.Count -gt 0) {
                    $step = $phaseSteps[0]
                }
            }

            # Apply going to a specific step.
            if ($null -eq $step -and $null -eq $currentStep.Adapter -and $currentStep.Activity -eq "Goto") {
                $IsEnabledSignal = Resolve-PathFromDictionary -Dictionary $currentStep -Path "IsEnabled" -Default $true | Select-Object -Last 1

                if ($this.TestAllTrue($IsEnabledSignal.GetResult())) {
                    $gotoName = $currentStep.Path # SetWeather_SelectSpecifiedTime_Exit
                    for ($i = 0; $i -lt $phaseSteps.Count; $i++) {
                        if ($phaseSteps[$i].Name -eq $gotoName) {
                            $skipSteps = $currentStep.Config.SkipSteps ?? 0
                            $step = $phaseSteps[$i + $skipSteps]
                            break;
                        }
                    }

                    # Try ends with if a direct match didn't work, this allows for a step name to be generated with an iteration suffix like _1, _2, etc.
                    if ($null -eq $step) {
                        for ($i = 0; $i -lt $phaseSteps.Count; $i++) {
                            if ($phaseSteps[$i].Name -like "*$gotoName") {
                                $skipSteps = $currentStep.Config.SkipSteps ?? 0
                                $step = $phaseSteps[$i + $skipSteps]
                                break;
                            }
                        }
                    }
                }

            }

            # Find current step and return the next one
            if ($null -eq $step) {
                for ($i = 0; $i -lt $phaseSteps.Count; $i++) {

                    if ($phaseSteps[$i].Name -eq $currentStep.Name) {
                        $nextIndex = $i + 1
                        if ($nextIndex -lt $phaseSteps.Count) {
                            $step = $phaseSteps[$nextIndex]
                        }

                        break
                    }
                }
            }
        }

        if ($null -eq $step) {
            return $null
        }

        $trackIteration = $step.Config.PreventReclone
        $iteration = 0
        if ($trackIteration) {
            $iterationSignal = Resolve-PathFromDictionary -Dictionary $step -Path "Config.Iteration" -Default 0 | Select-Object -Last 1
            $iteration = $iterationSignal.GetResult() + 1
            $null = Add-PathToDictionary -Dictionary $step -Path "Config.Iteration" -Value $iteration 
            #            $step.Name = "$($step.Name)_$($iteration)"
        }

        $step = (Resolve-ClonePlan -Plan $step | Select-Object -Last 1).GetResult()
        return $step
    }

    [Signal] RegisterSignal(
        [Signal]$itemSignal,
        [string]$Key,
        [Signal]$registerSignal) {
        if ($null -ne $Key -and $Key -ne "") {
            $itemSignal.Pointer.RegisterSignal($Key, $registerSignal)
        }

        return $itemSignal
    }

    [bool] TestAllTrue($Value) {
        $values = @($Value)

        if ($values.Count -eq 0) {
            return $false
        }

        foreach ($item in $values) {
            if ($null -eq $item) {
                return $false
            }

            if ($item -is [bool]) {
                if (-not $item) {
                    return $false
                }

                continue
            }

            if ($item.ToString().Trim().ToLowerInvariant() -eq "false") {
                return $false
            }

            if ($item.ToString().Trim().ToLowerInvariant() -ne "true") {
                return $false
            }
        }

        return $true
    }
}
