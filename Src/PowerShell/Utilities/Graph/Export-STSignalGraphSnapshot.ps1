function Export-STSignalGraphSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Signal]$ItemSignal,
        [Signal]$Signal
    )

    $opSignal = [Signal]::Start('Export-STSignalGraphSnapshot', $Signal) | Select-Object -Last 1
    try {
        $graph = $ItemSignal.GetPointer()
        if ($graph -isnot [Graph]) {
            throw 'ItemSignal does not have a Graph pointer.'
        }

        $records = foreach ($key in @($graph.Grid.Keys)) {
            $sourceSignal = $graph.Grid[$key]
            [PSCustomObject]@{
                Key       = [string]$key
                Name      = [string]$sourceSignal.Name
                Meta      = $sourceSignal.Meta
                HasResult = $sourceSignal.HasResult()
                Result    = if ($sourceSignal.HasResult()) { $sourceSignal.GetResult() } else { $null }
            }
        }

        $snapshot = [PSCustomObject]@{
            ItemName      = [string]$ItemSignal.Name
            ItemMeta      = $ItemSignal.Meta
            ItemHasResult = $ItemSignal.HasResult()
            ItemResult    = if ($ItemSignal.HasResult()) { $ItemSignal.GetResult() } else { $null }
            Signals       = @($records)
        }
        $json = ConvertTo-Json -InputObject $snapshot -Depth 100 -Compress -ErrorAction Stop

        # Parse once before returning so circular or unsupported values fail at launch.
        $null = ConvertFrom-Json -InputObject $json -Depth 100 -ErrorAction Stop
        $opSignal.SetResult($json)
    }
    catch {
        $null = $opSignal.LogCritical("Failed to export signal graph snapshot: $($_.Exception.Message)", $null, $_)
    }
    return $opSignal
}
