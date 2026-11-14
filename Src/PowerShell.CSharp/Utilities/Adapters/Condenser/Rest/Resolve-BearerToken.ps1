function Resolve-BearerToken {
    [CmdletBinding()]
    param(
        [object]$Plan,
        [string]$Address
    )

    $opSignal = [Signal]::Start("Resolve-BearerToken") | Select-Object -Last 1

    try {
        # Requires Azure CLI
        $tokenJson = az account get-access-token --resource=$Address
        if (-not $tokenJson) {
            $opSignal.LogCritical("❌ Resolve-BearerToken: az returned no token payload for resource '$resource'.")
            return $opSignal
        }

        $tokenObj = $tokenJson | ConvertFrom-Json
        $bearer = $tokenObj.accessToken

        if (-not $bearer) {
            $opSignal.LogCritical("❌ Resolve-BearerToken: accessToken missing in az output for resource '$resource'.")
            return $opSignal
        }

        $opSignal.SetResult($bearer)
        return $opSignal
    }
    catch {
        $opSignal.LogCritical("💥 Exception in Resolve-BearerToken: $($_.Exception.Message)")
        return $opSignal
    }
}
