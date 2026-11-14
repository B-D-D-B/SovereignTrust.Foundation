function Invoke-VisualizeSignalTreeTrace {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Signal]$JacketSignal,
        [Signal]$ResultSignal
    )

    $opSignal = [Signal]::Start("VisualizeSignalTreeTrace", $JacketSignal) | Select-Object -Last 1
    $opSignal.SetJacket($JacketSignal)

    if ($null -eq $ResultSignal) {
        $ResultSignal = Invoke-TraceSignalTree -Signal $JacketSignal | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure(@($ResultSignal))) {
            return $opSignal
        }
    }

    $diagramSignal = [Signal]::Start("SignalTree:Diagram", $ResultSignal) | Select-Object -Last 1
    $diagramSignal.SetJacket($ResultSignal)

    $allDiagramSignals = @()
    $entryQueue = [System.Collections.Generic.Queue[object]]::new()
    $entryQueue.Enqueue($ResultSignal)

    while ($entryQueue.Count -gt 0) {
        $current = $entryQueue.Dequeue()
        $entries = $current.GetEntries()

        $begin = Emit-SignalTreeBoundary -Target $diagramSignal -Direction "Begin" -TraceID $opSignal.Name -TraceScope "Replay" | Select-Object -Last 1
        if ($diagramSignal.MergeSignalAndVerifyFailure(@($begin))) {
            return $diagramSignal
        }

        foreach ($entry in $entries) {
            if ($entry -is [SignalEntry]) {
                if ($entry.Level -in @("Information", "ignoreVerbose") -and $entry.Message -like "*SignalTree:*") {
                    $emitLine = Emit-SignalTreeLine -Target $diagramSignal -Line $entry.Message -Level $entry.Level -TraceID $opSignal.Name -TraceScope "Replay" -Minimal $true | Select-Object -Last 1
                    $allDiagramSignals += $emitLine
                }
            }
        }

        if ($diagramSignal.MergeSignalAndVerifyFailure($allDiagramSignals)) {
            return $diagramSignal
        }

        $end = Emit-SignalTreeBoundary -Target $diagramSignal -Direction "End" -TraceID $opSignal.Name -TraceScope "Replay" | Select-Object -Last 1
        if ($diagramSignal.MergeSignalAndVerifyFailure(@($end))) {
            return $diagramSignal
        }
    }

    $opSignal.SetResult($diagramSignal)
    if ($opSignal.MergeSignalAndVerifyFailure(@($diagramSignal))) {
        return $opSignal
    }

    return $opSignal
}
