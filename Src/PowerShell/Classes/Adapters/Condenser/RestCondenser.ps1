# =============================================================================
# 🔐 RestCondenser (Graph Context + XPath Rest Resolution)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☠️🧁👾️/🤖 • Neural Alchemist ⚗️☣️🐲 • Last Updated: 05/20/2025
# =============================================================================
# Uses XPath-based Rest lookup with imported graph documents to resolve runtime
# variables within sovereign templates. This condenser class is central to hydration
# flows, Rest graph processing, and context-sensitive publishing.
# =============================================================================

class RestCondenser {
    [Conductor]$Conductor
    [MappedCondenserAdapter]$MappedCondenserAdapter
    [Signal]$Signal

    RestCondenser() {
        # Empty constructor — use Start()
    }

    static [RestCondenser] Start([MappedCondenserAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [RestCondenser]::new()
        $instance.MappedCondenserAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("RestCondenser.Control") | Select-Object -Last 1
        return $instance
    }

    [Signal] Invoke(
        [string]$Slot,
        [string]$Activity,
        [Signal]$ConductionSignal,
        [object]$Plan,
        [Signal]$ItemSignal
    ) {
        $opSignal = [Signal]::Start("RestCondenser.Invoke", $ItemSignal) | Select-Object -Last 1

        $skipBearerTokenSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.SkipBearerToken" -Default $false | Select-Object -Last 1

        $bearerTokenSignal = $skipBearerTokenSignal.GetResult() ? $null : $this.ResolveBearerToken($ConductionSignal, $Plan, $false)
        $headersSignal = $this.GetStorageVersionHeaders($ConductionSignal, $Plan)

        # Clone Plan before Mutate
        $clonePlan = (Resolve-ClonePlan -Plan $Plan | Select-Object -Last 1).GetResult()

        if ($headersSignal.HasResult()){
            Add-PathToDictionary -Dictionary $clonePlan -Path "Config.Headers" -Value $headersSignal.GetResult()
        }

        if ($bearerTokenSignal -and $bearerTokenSignal.HasResult()){
            Add-PathToDictionary -Dictionary $clonePlan -Path "Config.BearerToken" -Value $bearerTokenSignal.GetResult()
        }

        # Passing RestCondenser is an anti-pattern but I'm taking a short cut to passing back the result to inform the adapter to retry the bearer token because I want to come up with a pattern using
        # Signal with a recovery recommendation to inform the adapter to retry the bearer token. This is a temporary solution until I replace with a better pattern.
        $resultSignal = Invoke-RestCondenserCore -RestCondenser $this -Signal $ConductionSignal -Plan $clonePlan -ItemSignal $ItemSignal -Activity $Activity | Select-Object -Last 1
        $opSignal.MergeSignal($resultSignal)

        # TODO: The result will now hold recommendations if there is a failure, such as to clear bearer token and try again

        if ($resultSignal.HasResult()) {
            # TODO: Use Resolve-PathFromDictionary with $resultSignal for dictionary and "@.Response"
            $opSignal.SetResult($resultSignal.GetResult().Response)
        }

        return $opSignal
    }

[Signal] GetStorageVersionHeaders(
    [Signal]$ConductionSignal,
    [object]$Plan
) {
    $opSignal = [Signal]::Start("RestCondenser.GetStorageVersionHeaders", $ConductionSignal) | Select-Object -Last 1

    try {
        if (-not $Plan) {
            $opSignal.LogCritical("Plan is null.")
            return $opSignal
        }

        $headersSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Headers" -SignalLevel "Warning" | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure(@($headersSignal))) { return $opSignal }
        if ($headersSignal.HasResult()) {
            $opSignal.SetResult($headersSignal.GetResult())
            return $opSignal
        }

        # Resolve Url from plan
        $urlSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Uri" -SignalLevel "Warning" | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure(@($urlSignal))) { return $opSignal }

        $url = $urlSignal.GetResult()
        if ([string]::IsNullOrWhiteSpace($url)) {
            $opSignal.LogCritical("Plan.Uri was empty.")
            return $opSignal
        }

        # Strip Url from array if in an array.
        $url = (@($url))[0]

        # Parse URL
        try {
            $uri = [Uri]$url
            $hostAddress = $uri.DnsSafeHost.ToLowerInvariant()
            $port = $uri.Port
        }
        catch {
            $opSignal.LogCritical("Plan.Url is not a valid Uri: $($_.Exception.Message)")
            return $opSignal
        }

        # Azure Storage data-plane host detection
        $isStorageHost =
            ($hostAddress -match '\.(blob|queue|table|dfs)\.core\.') -or
            (($hostAddress -in @('localhost', '127.0.0.1')) -and ($port -in 10000, 10001, 10002))

        # Always return a headers object (empty if not storage)
        $headers = @{}

        if ($isStorageHost) {
            # Required for Storage auth (SharedKey, SAS, OAuth)
            $headers['x-ms-version'] = '2023-11-03'
            $headers['x-ms-date']    = (Get-Date).ToUniversalTime().ToString('R')  # RFC1123

            # Queue REST APIs are XML-first
            $headers['Accept'] = 'application/xml'

            $opSignal.LogInformation("✅ Azure Storage headers generated for host: $hostAddress")
            $opSignal.SetResult($headers)
        }
        else {
            $opSignal.LogVerbose("⏭️ Non-storage host detected; returning empty headers.")
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in RestCondenser.GetStorageVersionHeaders: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}


    [Signal] ResolveBearerToken(
        [Signal]$ConductionSignal,
        [object]$Plan,
        [bool]$ClearExistingFirst
    ) {
        $opSignal = [Signal]::Start("RestCondenser.ResolveBearerToken", $ConductionSignal) | Select-Object -Last 1

        try {
            if (-not $ConductionSignal) {
                $opSignal.LogCritical("ConductionSignal is null.")
                return $opSignal
            }

            if (-not $Plan) {
                $opSignal.LogCritical("Plan is null.")
                return $opSignal
            }

            # --- Host ---
            $hostSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Host" -SignalLevel "Warning" | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure(@($hostSignal))) { return $opSignal }

            $hostAddress = $hostSignal.GetResult()
            if (-not $hostAddress) {
                $opSignal.LogCritical("Plan.Host was empty.")
                return $opSignal
            }

            # --- Ensure AccessTokens graph exists on the ConductionSignal ---
            # Convention: store graphs on the ConductionSignal's jacket/memory path.
            $tokensGraphPath = "%.*.#.AccessTokens"

            $tokensGraphResolve = Resolve-PathFromDictionary -Dictionary $ConductionSignal -Path $tokensGraphPath -SignalLevel "Information" | Select-Object -Last 1

            $tokensGraph = $null
            if ($tokensGraphResolve.HasResult()) {
                $tokensGraph = $tokensGraphResolve.GetResult($true)
            }
            else {
                # Create a graph and store it back under the path
                $tokensGraphSignal = [Graph]::Start("AccessTokens", $ConductionSignal, $false) | Select-Object -Last 1
                if ($opSignal.MergeSignalAndVerifyFailure(@($tokensGraphSignal))) { return $opSignal }

                $tokensGraph = $tokensGraphSignal.GetResult($true)

                $storeSignal = Add-PathToDictionary -Dictionary $ConductionSignal -Path $tokensGraphPath -Value $tokensGraph | Select-Object -Last 1
                if ($opSignal.MergeSignalAndVerifyFailure(@($storeSignal))) { return $opSignal }
            }

            if (-not $tokensGraph) {
                $opSignal.LogCritical("Failed to resolve or create AccessTokens graph.")
                return $opSignal
            }

            # --- Resolve existing token signal (if any) ---
            $existingTokenSignal = $tokensGraph.Resolve($hostAddress) | Select-Object -Last 1
            $opSignal.MergeSignal(@($existingTokenSignal)) | Out-Null

            $hasExisting = $existingTokenSignal.HasResult() -and $null -ne $existingTokenSignal.GetResult()

            if ($ClearExistingFirst -and $tokensGraph.Grid.Contains($hostAddress)) {
                $removeSignal = $tokensGraph.UnRegisterSignal($hostAddress) | Select-Object -Last 1
                $opSignal.MergeSignal(@($removeSignal)) | Out-Null
                $hasExisting = $false
            }

            if ($hasExisting) {
                $opSignal.SetResult($existingTokenSignal.GetResult())
                $opSignal.LogInformation("✅ Bearer token cache hit for host: $hostAddress")
                return $opSignal
            }

            # --- Acquire new token ---
            # NOTE: Resolve-BearerToken is assumed to exist in your module.
            $bearerTokenSignal = Resolve-BearerToken -Address $hostAddress | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure(@($bearerTokenSignal))) { return $opSignal }

            $token = $bearerTokenSignal.GetResult($true)
            if (-not $token) {
                $opSignal.LogCritical("Resolve-BearerToken returned empty token.")
                return $opSignal
            }

            # Register token in graph as a Signal (so it’s traceable + consistent)
            $tokenSignal = [Signal]::Start("BearerToken:$hostAddress", $ConductionSignal) | Select-Object -Last 1
            $tokenSignal.SetResult($token)

            $registerSignal = $tokensGraph.RegisterSignal($hostAddress, $tokenSignal) | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure(@($registerSignal))) { return $opSignal }

            $opSignal.SetResult($token)
            $opSignal.LogInformation("✅ Bearer token resolved and cached for host: $hostAddress")
        }
        catch {
            $opSignal.LogCritical("🔥 Exception in ResolveBearerToken: $($_.Exception.Message)", $null, $_)
        }

        return $opSignal
    }

}
