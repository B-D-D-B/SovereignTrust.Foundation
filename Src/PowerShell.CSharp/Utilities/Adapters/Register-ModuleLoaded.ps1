function Register-ModuleLoaded {
    param (
        [Parameter(Mandatory = $true)][object]$ModulesGraph,
        [Parameter(Mandatory = $true)][string]$ModuleName,
        [string]$FullPath,
        [string]$Version
    )

    $signal = [Signal]::Start("Register-ModuleLoaded:$ModuleName") | Select-Object -Last 1

    # ░▒▓█ MODULE LOADED MEMORY █▓▒░
    $moduleJacket = @{
        FullPath = $FullPath
        Version  = $Version
        Loaded   = $true
    }

    $moduleSignal = [Signal]::new($ModuleName)
    $moduleSignal.SetResult($moduleJacket)
    $moduleSignal.LogInformation("✅ Module '$ModuleName' marked as loaded with version $Version.")

    # ░▒▓█ REGISTER TO GRAPH █▓▒░
    try {
        $ModulesGraph.RegisterSignal($ModuleName, $moduleSignal)
        $signal.LogInformation("📦 Signal '$ModuleName' registered in ModulesGraph.")
    }
    catch {
        $signal.LogCritical("Failed to register module '$ModuleName': $($_.Exception.Message)")
    }

    $signal.SetResult($ModulesGraph)
    return $signal
}
