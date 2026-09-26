# =============================================================================
# 🧠 SDA FormatCondenser
#  SovereignTrust Memory Interface for performing Invoke-FormatCondenser calls
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom 🤖/☠️🧁👾️ • Neural Alchemist ⚗️☣️🐲 • Version: 2025.5.4.8
# =============================================================================

class FormatCondenser {
    [Signal]$Signal

    FormatCondenser() {}

    static [Signal] Start([MappedCondenserAdapter]$adapter, [Conductor]$conductor) {
        $opSignal = [Signal]::Start("FormatCondenser.Start") | Select-Object -Last 1

        $instance = [FormatCondenser]::new()
        $instance.Signal = [Signal]::Start("FormatCondenser", $adapter) | Select-Object -Last 1
        $instance.Signal.SetJacket($conductor) | Out-Null

        $opSignal.SetResult($instance)
        $opSignal.LogInformation("✅ FormatCondenser initialized.")
        return $opSignal
    }

    [Signal]Invoke([string]$Slot, [string]$Activity, [Signal]$ConductionSignal, [object]$Plan, [Signal]$ItemSignal) {
        $opSignal = [Signal]::Start("FormatCondenser.Invoke", $ItemSignal) | Select-Object -Last 1

        $DefaultPath = "%.@"
        if ($Activity) {
            switch ($Activity) {
                "Json" {
                    $contentSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $DefaultPath | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($contentSignal)) {
                        $opSignal.LogCritical("Failed to resolve content at path: $DefaultPath")
                        return $opSignal
                    }

                    $content = $contentSignal.GetResult()

                    # Invoke-FormatJson should receive the JSON text (or object) directly, not via -Path unless it truly expects a file path
                    $resultSignal = Invoke-FormatJson -Path $content -Plan $Plan | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)) {
                        $opSignal.LogCritical("JSON formatting failed.")
                        return $opSignal
                    }

                    $opSignal.SetResult($resultSignal.GetResult())
                    break
                }

                "JsonArray" {
                    $contentSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $DefaultPath | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($contentSignal)) {
                        $opSignal.LogCritical("Failed to resolve content at path: $DefaultPath")
                        return $opSignal
                    }

                    $content = $contentSignal.GetResult()

                    # Invoke-FormatJson should receive the JSON text (or object) directly, not via -Path unless it truly expects a file path
                    $resultSignal = Invoke-FormatJson -Path $content -Plan $Plan | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)) {
                        $opSignal.LogCritical("JSON formatting failed.")
                        return $opSignal
                    }

                    $opSignal.SetResult($resultSignal.GetResult())
                    break
                }

                "Xml" {
                    $contentSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $DefaultPath | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($contentSignal)) {
                        $opSignal.LogCritical("Failed to resolve content at path: $DefaultPath")
                        return $opSignal
                    }

                    $content = $contentSignal.GetResult()
                    if ($content -is [System.Xml.XmlDocument])
                    {
                        $resultSignal = $contentSignal
                    }
                    else {
                        # Invoke-FormatXml should receive the Xml text (or object) directly, not via -Path unless it truly expects a file path
                        $resultSignal = Invoke-FormatXml -Path $content | Select-Object -Last 1
                        if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)) {
                            $opSignal.LogCritical("JSON formatting failed.")
                            return $opSignal
                        }
                    }

                    $opSignal.SetResult($resultSignal.GetResult())
                    break
                }

                "Text" {
                    $contentSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $DefaultPath | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($contentSignal)) {
                        $opSignal.LogCritical("Failed to resolve content at path: $DefaultPath")
                        return $opSignal
                    }

                    $content = $contentSignal.GetResult()
                    switch ($content.GetType().FullName)
                    {
                        'System.Xml.XmlDocument' {
                            $content = $content.OuterXml
                            break
                        }
                        'System.Management.Automation.PSCustomObject' {
                            $content = ($content | ConvertTo-Json -Depth 100 -Compress)
                            break
                        }
                        default {
                            break
                        }
                    }

                    $opSignal.SetResult($content)
                    break
                }

                default {
                    $opSignal.LogWarning("Unsupported Activity: $Activity")
                    break
                }
            }
        }

        return $opSignal
    }


    [Signal] InvokeByParameter(
        [string]$Action,
        [string]$Path,
        [object]$Value,
        [object]$TargetMemory,
        [hashtable]$HydrationPlan,
        [string]$HotPathMapPath = "%.HotPaths"
    ) {
        $opSignal = [Signal]::Start("FormatCondenser.InvokeByParameter", $this.Signal) | Select-Object -Last 1

        # 🔍 Step 1: Hot Path Resolution
        $hotPathSignal = Invoke-HotPathResolution -Path $Path -Signal $this.Signal -HotPathMapPath $HotPathMapPath | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($hotPathSignal)) {
            $opSignal.LogCritical("Hot path resolution failed.")
            return $opSignal
        }

        $resolvedHotPath = $hotPathSignal.GetResult()

        # 💧 Step 2: Path Hydration
        $hydratedSignal = Invoke-PathHydration -Path $resolvedHotPath -Signal $this.Signal -SignalFirst:$true | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($hydratedSignal)) {
            $opSignal.LogCritical("Path hydration failed.")
            return $opSignal
        }

        $finalPath = $hydratedSignal.GetResult()

        # 🧠 Step 3: Memory I/O Delegation
        $memorySignal = Invoke-FormatCondenser -Action $Action -Path $finalPath -Value $Value -HostSignal $this.Signal -TargetMemory $TargetMemory -HydrationPlan @{ Skip = $true } | Select-Object -Last 1
        $opSignal.MergeSignal($memorySignal)

        return $opSignal
    }
}
