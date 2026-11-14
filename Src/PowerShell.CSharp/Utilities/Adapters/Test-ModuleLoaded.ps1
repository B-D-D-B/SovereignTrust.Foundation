function Test-ModuleLoaded {
    param (
        [Parameter(Mandatory = $true)][object]$ModulesGraph,
        [Parameter(Mandatory = $true)][string]$ModuleName
    )

    $signal = [Signal]::Start("Test-ModuleLoaded:$ModuleName") | Select-Object -Last 1

    # ░▒▓█ RESOLVE MODULE SIGNAL █▓▒░
    $resolveSignal = Resolve-PathFromDictionary -Dictionary $ModulesGraph -Path "$ModuleName.Result.Loaded" | Select-Object -Last 1
    $signal.MergeSignal(@($resolveSignal))

    if ($resolveSignal.Success() -and ($resolveSignal.GetResult() -eq $true)) {
        $signal.SetResult($true)
        $signal.LogInformation("✅ Module '$ModuleName' is marked as loaded.")
    } else {
        $signal.SetResult($false)
        $signal.LogVerbose("⏳ Module '$ModuleName' is not yet marked as loaded.")
    }

    return $signal
}
