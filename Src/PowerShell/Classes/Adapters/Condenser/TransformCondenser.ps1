# =============================================================================
# 🔄 TransformCondenser
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☠️🧁👾️/🤖 • Neural Alchemist ⚗️☣️🐲 • Last Updated: 10/16/2026
# =============================================================================
# Transforms content and manages registered signals.
#
# Supported activities:
# • Project: Finds source nodes in ItemSignal using Plan.Key, retrieves shared
#   content from Token.Memory at Plan.Path, and applies deferred hydration to
#   each node using Plan.Config. Returns the collected hydration results.
# • Select: Reads content from ItemSignal at Config.DefaultPath (default: %.@)
#   and selects Plan.Path through Invoke-TransformSelect using Plan.Format and
#   Plan.HtmlDecode (default: true). Config.Hydrate optionally applies deferred
#   hydration with Plan.Config before returning the selected content.
# • Inject: Appends Config.Content to ItemSignal at Plan.Path.
# • RegisterSignal: Registers the signal returned by resolving Config.Content
#   on the ItemSignal pointer under Config.Key.
# • UnregisterSignalKeys: Removes each key in Config.Keys from the ItemSignal
#   pointer's registered signals.
# • Clone: Resolves Plan.Path from ItemSignal and returns a copy produced by
#   a JSON round trip with serialization and deserialization depth set to 10.
# • Merge: Merges Base and Overlay from ItemSignal beneath Config.DefaultPath
#   (default: %.@) through Invoke-MergeJson. Reads MergeArrayHandling (default:
#   Merge), MergeNullValueHandling (default: Ignore), and Depth (default: 100)
#   from the same source location and returns the merged result on success.
#
# Invoke returns an operation Signal; unsupported activities log a critical error.
#
# Check Doctrine Alignment:
# • Sovereign Memory: ✅
# • Living Signals: ✅
# • Adapter Evolution: ✅
# • Temporal Recursion: ✅
# =============================================================================

<#
Class: TransformCondenser
Purpose: Perform transform condenser operations.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- Project: Project signal data.
- Select: Select signal data.
- Inject: Inject signal data.
- RegisterSignal: Register a signal.
- UnregisterSignalKeys: Remove registered signal keys.
- Clone: Clone signal data.
- Merge: Merge signal data.
ActivityValidation: OnInvoke, BeforeDispatch
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
#>
class TransformCondenser {
    [Conductor]$Conductor
    [MappedCondenserAdapter]$MappedCondenserAdapter
    [Signal]$Signal  # Sovereign control signal (previously ControlSignal)

    TransformCondenser() {
    }

    static [TransformCondenser] Start([MappedCondenserAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [TransformCondenser]::new()
        $instance.MappedCondenserAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("TransformCondenser.Control") | Select-Object -Last 1
        return $instance
    }

    [Signal]Invoke([string]$Slot, [string]$Activity, [Signal]$ConductionSignal, [object]$Plan, [Signal]$ItemSignal) {
        $opSignal = [Signal]::Start("TransformCondenser.Invoke") | Select-Object -Last 1

        if ($Activity -notin @('Project', 'Select', 'Inject', 'RegisterSignal', 'UnregisterSignalKeys', 'Clone', 'Merge')) {
            $opSignal.LogCritical("Unsupported TransformCondenser activity: '$Activity'.")
            return $opSignal
        }

        # First Supported Activities -> Select, Merge, Project
        $DefaultPathSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.DefaultPath" -Default "%.@" -SignalLevel "Warning" | Select-Object -Last 1
        $DefaultPath = $DefaultPathSignal.GetResult()
        if ($Activity) {
            switch ($Activity) {

                # Select using a path from an xml or json object.
                "Project" {
                    # This should generally be done after a mapping has pushed an adapter call into the Grid memory of the ItemSignal, attempt to use the Plan's Key to look for them.
                    $KeySignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Key" -SignalLevel "Warning" | Select-Object -Last 1
                    $result = @()

                    if ($KeySignal.HasResult())
                    {
                        $SourceTransformNodesSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "*.#.$($KeySignal.GetResult())" | Select-Object -Last 1
                        if ($SourceTransformNodesSignal.HasResult())
                        {
                            $ContentPlan = [PSCustomObject]@{
                                Path = $Plan.Path
                                HydrationPlan = "@"
                            }

                            $SourceContentResultSignal = Invoke-MappedAdapter -Adapter "Token.Memory"  -Activity "Get" -Plan $ContentPlan -ItemSignal $ItemSignal -Signal $ConductionSignal | Select-Object -Last 1
                            if ($SourceContentResultSignal.HasResult())
                            {
                                $null = Add-PathToDictionary -Dictionary $ContentPlan -Path "HydrationPlan" -Value "@"
                                $content = $SourceContentResultSignal.GetResult()                             
                                $nodes = @($SourceTransformNodesSignal.GetResult().GetResult())

                                foreach ($node in $nodes)
                                {
                                    $HydrationPlan = [PSCustomObject]@{
                                        Path = "%.@"
                                        HydrationPlan = "@"
                                        HydrationStyle = "Deferred"
                                        Source = "TransformCondenser"
                                        Config = $Plan.Config
                                    }

                                    #$null = Add-PathToDictionary -Dictionary $ContentPlan -Path "Config" -Value $node
                                    $HydrationSignal = [Signal]::Start("TransformCondenser.Invoke.Hydration") | Select-Object -Last 1
                                    $SourceContentResultSignal.SetResult($content)
                                    $HydrationSignal.SetJacket($SourceContentResultSignal)
                                    $HydrationSignal.SetPointer($ItemSignal.GetPointer())
                                    $HydrationSignal.SetResult($node)
                                    
                                    # Perform Hydration
                                    $MappingResultSignal = Invoke-CondenserAdapter -Slot "Hydration" -Plan $HydrationPlan -Signal $ConductionSignal -ItemSignal $HydrationSignal | Select-Object -Last 1
                                    #$this.RegisterSignal($ItemSignal, $Key, $MappingResultSignal)
                                    $signResult = "a"

                                    
                                    $result += $MappingResultSignal.GetResult()
                                }
                            }
                            
                        }
                    }

                    $opSignal.SetResult($result)
                    break
                }

                # Select using a path from an xml or json object.
                # TODO: We should remove the Path and hydration portions of this and do it through the standard memory condenser. Will need to coordinate with changing the plans that use select.
                "Select" {
                    $sourceSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $DefaultPath | Select-Object -Last 1

                    $sourcePathSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Path" | Select-Object -Last 1
                    $sourceFormatSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Format" -Default ""  | Select-Object -Last 1
                    $SourceHtmlDecodeSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "HtmlDecode" -Default $true | Select-Object -Last 1

                    $hydrateSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Hydrate" -Default $false | Select-Object -Last 1

                    if ($opSignal.MergeSignalAndVerifyFailure($sourceSignal) -or $opSignal.MergeSignalAndVerifyFailure($sourcePathSignal) -or $opSignal.MergeSignalAndVerifyFailure($sourceFormatSignal) -or $opSignal.MergeSignalAndVerifyFailure($SourceHtmlDecodeSignal)) {
                        $opSignal.LogCritical("Failed to resolve content for Transform")
                        return $opSignal
                    }

                    $source = $sourceSignal.GetResult()

                    # Invoke-FormatJson should receive the JSON text (or object) directly, not via -Path unless it truly expects a file path
                    $resultSignal = Invoke-TransformSelect -Source $source -SourcePath $sourcePathSignal.GetResult() -SourceFormat $sourceFormatSignal.GetResult() -SourceHtmlDecode $SourceHtmlDecodeSignal.GetResult() | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)) {
                        $opSignal.LogCritical("JSON formatting failed.")
                        return $opSignal
                    }

                    if ($hydrateSignal.GetResult())
                    {
                        $HydrationPlan = [PSCustomObject]@{
                            Path = "%.@"
                            HydrationPlan = "@"
                            HydrationStyle = "Deferred"
                            Source = "TransformCondenser"
                            Config = $Plan.Config
                        }

                        #$null = Add-PathToDictionary -Dictionary $ContentPlan -Path "Config" -Value $node
                        $HydrationSignal = [Signal]::Start("TransformCondenser.Invoke.Hydration") | Select-Object -Last 1
                        $HydrationSignal.SetJacket($resultSignal)
                        $HydrationSignal.SetPointer($ItemSignal.GetPointer())
#                        $HydrationSignal.SetResult($node)
                        
                        # Perform Hydration
                        $MappingResultSignal = Invoke-CondenserAdapter -Slot "Hydration" -Plan $HydrationPlan -Signal $ConductionSignal -ItemSignal $HydrationSignal | Select-Object -Last 1

                        
                        $resultSignal.SetResult($MappingResultSignal.GetResult())
                    }

                    $opSignal.SetResult($resultSignal.GetResult())
                    break
                }

                # Injects using a path to an xml or json object.
                "Inject" {
                    $sourceSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Content" | Select-Object -Last 1
                    $null = Add-PathToDictionary -Dictionary $ItemSignal -AddStyle "Append" -Path $Plan.Path -Value $sourceSignal.GetResult() | Select-Object -Last 1
                    break
                }

                # Injects using a path to an xml or json object.
                "RegisterSignal" {
                    $sourceSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Content" | Select-Object -Last 1
                    $keySignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Key" | Select-Object -Last 1

                    $ItemSignal.GetPointer().RegisterSignal($keySignal.GetResult(), $sourceSignal);
                    break
                }

                "UnregisterSignalKeys" {
                    $pointer = $ItemSignal.GetPointer()
                    $keysSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Keys" | Select-Object -Last 1

                    foreach ($key in @($keysSignal.GetResult())) {
                        $pointer.UnregisterSignal($key)
                    }
                    break
                }

                # Clone using a path to an xml or json object.
                "Clone" {
                    $pathSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Path" | Select-Object -Last 1

                    $path = $pathSignal.GetResult()

                    $sourceSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $path | Select-Object -Last 1
                    $source = $sourceSignal.GetResult() | ConvertTo-Json -Depth 10 | ConvertFrom-Json -Depth 10
                    
                    $opSignal.SetResult($source )
                    break
                }

                # Merges Json objects or builds an array
                "Merge" {

                    $BaseSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "$DefaultPath.Base" | Select-Object -Last 1
                    $OverlaySignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "$DefaultPath.Overlay" | Select-Object -Last 1
                    $MergeArrayHandlingSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "$DefaultPath.MergeArrayHandling" -Default "Merge" | Select-Object -Last 1
                    $MergeNullValueHandlingSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "$DefaultPath.MergeNullValueHandling" -Default "Ignore" | Select-Object -Last 1
                    $DepthSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "$DefaultPath.Depth" -Default 100 | Select-Object -Last 1

                    if ($opSignal.MergeSignalAndVerifyFailure($BaseSignal) -or $opSignal.MergeSignalAndVerifyFailure($OverlaySignal)) {
                        $opSignal.LogCritical("Failed to resolve content for Transform")
                        return $opSignal
                    }

                    $MergeResultSignal = Invoke-MergeJson -Base $BaseSignal.GetResult() -Overlay $OverlaySignal.GetResult() -MergeArrayHandling $MergeArrayHandlingSignal.GetResult() -MergeNullValueHandling $MergeNullValueHandlingSignal.GetResult() -Depth $DepthSignal.GetResult() | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifySuccess($MergeResultSignal)) {
                        $opSignal.SetResult($MergeResultSignal.GetResult())
                    }
                    break
                }

                default {
                    $opSignal.LogCritical("Unsupported Activity: $Activity")
                    break
                }
            }
        }

        return $opSignal
    }
}
