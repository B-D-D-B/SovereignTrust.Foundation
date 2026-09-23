function Import-STSignalGraphSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SnapshotJson,
        [Parameter(Mandatory)][Signal]$ConductionSignal,
        [string]$Name = 'BackgroundPhaseItem'
    )

    $opSignal = [Signal]::Start('Import-STSignalGraphSnapshot', $ConductionSignal) | Select-Object -Last 1
    try {
        $snapshot = ConvertFrom-Json -InputObject $SnapshotJson -Depth 100 -ErrorAction Stop
        $targetGraph = $ConductionSignal.GetPointer()
        if ($targetGraph -isnot [Graph]) {
            throw 'Worker ConductionSignal does not have a Graph pointer.'
        }

        foreach ($record in @($snapshot.Signals)) {
            # Preserve the freshly initialized runtime's environment registrations.
            if ($targetGraph.Grid.Contains([string]$record.Key)) { continue }

            $importedSignal = [Signal]::Start([string]$record.Name, $ConductionSignal) | Select-Object -Last 1
            if ($null -ne $record.Meta) { $importedSignal.SetMeta($record.Meta) }
            if ([bool]$record.HasResult) { $importedSignal.SetResult($record.Result) }
            $registerSignal = $targetGraph.RegisterSignal([string]$record.Key, $importedSignal) | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure($registerSignal)) { return $opSignal }
        }

        $itemSignal = [Signal]::Start($Name, $ConductionSignal) | Select-Object -Last 1
        $null = $itemSignal.SetPointer($targetGraph)
        if ($null -ne $snapshot.ItemMeta) { $itemSignal.SetMeta($snapshot.ItemMeta) }
        if ([bool]$snapshot.ItemHasResult) { $itemSignal.SetResult($snapshot.ItemResult) }
        $opSignal.SetResult($itemSignal)
    }
    catch {
        $null = $opSignal.LogCritical("Failed to import signal graph snapshot: $($_.Exception.Message)", $null, $_)
    }
    return $opSignal
}
