function Resolve-GraphHydrationQueue {
    param (
        [Parameter(Mandatory)][Graph]$Graph
    )
    $signal = [Signal]::Start("Resolve-GraphHydrationQueue") | Select-Object -Last 1
    try {
        $queueSignal = Resolve-PathFromDictionary -Dictionary $Graph -Path "HydrationQueue" | Select-Object -Last 1
        if ($queueSignal.Failure()) {
            $signal.LogInformation("🧼 No hydration queue present — nothing to process.")
            return $signal
        }
        $intentList = $queueSignal.GetResult()
        if (-not ($intentList -is [System.Collections.IEnumerable])) {
            $signal.LogWarning("HydrationQueue is not a list — skipping.")
            return $signal
        }
        $invokeSignal = Invoke-ApplyHydrationCondenser -Graph $Graph -Intent $intentList | Select-Object -Last 1
        $signal.MergeSignal($invokeSignal)
        if ($invokeSignal.Success()) {
            $signal.LogInformation("✅ Hydration queue processed.")
        } else {
            $signal.LogWarning("One or more hydration intents failed during processing.")
        }
    } catch {
        $signal.LogCritical("🔥 Exception while processing hydration queue: $($_.Exception.Message)", $null, $_)
    }
    return $signal
}