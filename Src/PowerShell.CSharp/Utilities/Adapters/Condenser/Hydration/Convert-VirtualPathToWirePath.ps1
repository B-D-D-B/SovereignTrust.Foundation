function Convert-VirtualPathToWirePath {
    param (
        [Parameter(Mandatory)][object]$Dictionary,
        [string]$Path = "VirtualPath"
    )

    $signal = [SignalGraph.Signal]::Start("Convert-VirtualPathToWirePath") | Select-Object -Last 1

    try {
        # ░▒▓█ RESOLVE PATH FROM DICTIONARY █▓▒░
        $resolveSignal = Resolve-PathFromDictionary -Dictionary $Dictionary -Path $Path | Select-Object -Last 1
        if ($signal.MergeSignalAndVerifySuccess($resolveSignal)) {
            $wirePath = $resolveSignal.GetResult()
            $signal.SetResult($wirePath)
            $signal.LogInformation("✅ WirePath resolved from '$Path': $wirePath")
        } else {
            $signal.LogCritical("❌ Path resolution failed for '$Path'.")
        }
    }
    catch {
        $signal.LogCritical("🔥 Unhandled exception in Convert-VirtualPathToWirePath: $($_.Exception.Message)")
    }

    return $signal
}
