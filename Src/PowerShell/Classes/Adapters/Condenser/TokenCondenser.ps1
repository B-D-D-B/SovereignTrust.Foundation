# =============================================================================
# 🔐 TokenCondenser (Graph Context + XPath Token Resolution)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☠️🧁👾️/🤖 • Neural Alchemist ⚗️☣️🐲 • Last Updated: 05/20/2025
# =============================================================================
# Uses XPath-based token lookup with imported graph documents to resolve runtime
# variables within sovereign templates. This condenser class is central to hydration
# flows, token graph processing, and context-sensitive publishing.
# =============================================================================

class TokenCondenser {
    [Conductor]$Conductor
    [MappedCondenserAdapter]$MappedCondenserAdapter
    [Signal]$Signal

    TokenCondenser() {
        # Empty constructor — use Start()
    }

    static [TokenCondenser] Start([MappedCondenserAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [TokenCondenser]::new()
        $instance.MappedCondenserAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("TokenCondenser.Control") | Select-Object -Last 1
        return $instance
    }

        


    [Signal] Invoke([string]$Slot, [string]$Activity, $ConductionSignal, $Plan, $ItemSignal) {
        $opSignal = [Signal]::Start("TokenCondenser.Invoke", $ItemSignal) | Select-Object -Last 1


        # Key is used in the plan to perform the token parsing, $ItemSignal contains the path as the result
        $Path = $ItemSignal.HasResult() ? $ItemSignal.GetResult() : $ItemSignal.GetJacket().GetResult()
        
        $Slot = ($Path -Split '\.')[0]
        $TokenAdapterPlan = [PSCustomObject]@{
            Path = $Path
        }

        $TokenParseSignal = Invoke-MappedAdapter -Adapter "Token.$Slot" -Activity "Get" -Plan $TokenAdapterPlan -Signal $ConductionSignal -ItemSignal $ItemSignal | Select-Object -Last 1

        if ($TokenParseSignal.HasResult())
        {
            $opSignal.SetResult($TokenParseSignal.GetResult())
        }

        return $opSignal

        # Now in MapCondenser as Direct route.
        # Require Result or Jacket to have value.
        $result = $ItemSignal.HasResult() ? $ItemSignal.GetResult() : $ItemSignal.GetJacket().GetResult()

        $ItemProxySignal = $ItemSignal

        if ($result -is [string]) {
            $resultObject = [pscustomobject]@{
                Message = $result
            }
            # Generate a new object to act as the Signle to pass in as a proxy
            $ItemSignal.SetResult($resultObject)

        }

        $condenserResult = Invoke-JsonTokenCondenser -Signal $ConductionSignal -ItemSignal $ItemSignal -Plan $Plan | Select-Object -Last 1

        if ($result -is [string]) {
            $messageObject = $condenserResult.GetResult()

            $opSignal.SetResult($messageObject.Message);
        }
        else {
            $opSignal.SetResult($condenserResult.GetResult());
        }

        # Need to overwrite the $ItemSignal result so the old one isn't used by the caller.
        $ItemSignal.SetResult($opSignal.GetResult())
        return $opSignal
    }

    [Signal] GetToken([string]$Value, $CondenserSignal, [bool]$ThrowExceptionOnEmpty = $true, [int]$RetryAttempts = 2) {
        $opSignal = [Signal]::Start("GetToken:$Value") | Select-Object -Last 1

        if ([string]::IsNullOrWhiteSpace($Value)) {
            $opSignal.LogWarning("Token value was empty or null.")
            return $opSignal
        }

        $firstLookup = $Value.IndexOf(".")
        if ($firstLookup -lt 0) {
            $opSignal.LogWarning("Token missing required lookup structure (e.g., no dot separator): $Value")
            return $opSignal
        }

        $tokenGraphFilePath = $Value.Substring(0, $firstLookup)
        $xpath = "/" + $Value.Substring($firstLookup).Replace(".", "/").Replace("[", "[@").Replace("[@@", "[@")

        $matchingNavigators = $CondenserSignal.Context.FindMatchingContextDictionary($tokenGraphFilePath)
        $opSignal.MergeSignal(@($matchingNavigators))

        $navigators = $matchingNavigators.GetResult()
        if (-not $navigators -or $navigators.Count -eq 0) {
            $opSignal.LogCritical("Token graph dictionary not found for: $Value")
            return $opSignal
        }

        foreach ($navigator in $navigators) {
            try {
                $node = $navigator.SelectSingleNode($xpath)
                if ($node) {
                    $opSignal.SetResult($node.InnerXml)
                    $opSignal.LogInformation("Token successfully resolved: $Value → $($node.InnerXml)")
                    return $opSignal
                }
            }
            catch {
                $opSignal.LogWarning("Navigator exception for path '$xpath': $_")
            }
        }

        $opSignal.LogCritical("Token not resolved — node not found at: $xpath")
        return $opSignal
    }

    [Signal] GetContext($TokenDocument, $TokenGraphOverrides, $OverloadGraphVirtualPath = $null) {
        $opSignal = [Signal]::Start("GetContext") | Select-Object -Last 1

        try {
            $settings = $this.GetMergeCondenserSettings()
            $nodeName = $settings.CondenserSettingsNodeName

            $tokenGraphsSignal = if ($TokenDocument -is [Newtonsoft.Json.Linq.JToken]) {
                [Signal]::Start($TokenDocument.SelectToken($nodeName)) | Select-Object -Last 1
            }
            else {
                Resolve-PathFromDictionary -Dictionary $TokenDocument -Path $nodeName
            }

            $opSignal.MergeSignal(@($tokenGraphsSignal))
            $tokenGraphs = $tokenGraphsSignal.GetResult()

            if (-not $tokenGraphs) {
                $opSignal.LogWarning("Tokens node '$nodeName' not found in TokenDocument.")
                return $opSignal
            }

            $graphsNode = $tokenGraphs[$settings.TokensNodeName][$settings.GraphNodeName]
            if (-not $graphsNode) {
                $opSignal.LogWarning("Graph node '$($settings.GraphNodeName)' not found under Tokens.")
                return $opSignal
            }

            $tokenGraphRoot = $graphsNode[$settings.TokenGraphRootNodeName]
            $importListRaw = $graphsNode[$settings.ImportNodeName]
            if (-not $tokenGraphRoot -or -not $importListRaw) {
                $opSignal.LogWarning("Missing tokenGraphRoot or importList.")
                return $opSignal
            }

            $context = @{}

            $replacements = $graphsNode["replacements"]
            if ($replacements) {
                $context.Replacements += (ConvertFrom-Json (ConvertTo-Json $replacements))
            }

            $importList = @(ConvertFrom-Json (ConvertTo-Json $importListRaw))

            if ($TokenGraphOverrides) {
                $overrideImports = $TokenGraphOverrides[$settings.ImportNodeName]
                if ($overrideImports) {
                    $importList += @(ConvertFrom-Json (ConvertTo-Json $overrideImports))
                }

                $overrideReplacements = $TokenGraphOverrides["replacements"]
                if ($overrideReplacements) {
                    $context.Replacements += (ConvertFrom-Json (ConvertTo-Json $overrideReplacements))
                }
            }

            foreach ($tokenGraph in ($importList | Invoke-SortDictionary -Unique)) {
                $relativePath = $tokenGraph.Replace("\", "/")
                $adjustedBasePath = $tokenGraphRoot

                if ($relativePath.Contains("/")) {
                    $splitParts = $relativePath.Split("/")
                    $relativePath = $splitParts[-1]
                    $adjustedBasePath = Join-Path -Path $tokenGraphRoot -ChildPath ($tokenGraph.Replace($relativePath, ""))
                }

                $graphSignal = $this.Conductor.MappedStorageService.ReadXmlXpath(
                    $relativePath, $null, $adjustedBasePath, $null, "Documents"
                )

                if ($opSignal.MergeSignalAndVerifySuccess(@($graphSignal))) {
                    $context.ContextNavigator[$relativePath] = $graphSignal.GetResult().CreateNavigator()
                }
                else {
                    $opSignal.LogCritical("Aborted graph loading due to failed resolution of: $relativePath")
                    return $opSignal
                }
            }

            $opSignal.SetResult($context)
            $opSignal.LogInformation("✅ Token context environment built successfully.")
            return $opSignal
        }
        catch {
            $opSignal.LogCritical("Exception in GetContext: $($_.Exception.Message)", $null, $_)
            return $opSignal
        }
    }
}
