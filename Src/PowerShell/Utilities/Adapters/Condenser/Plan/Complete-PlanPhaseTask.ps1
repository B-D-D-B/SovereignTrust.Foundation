function Complete-PlanPhaseTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][Signal]$ItemSignal,
        [Signal]$Signal,
        [ValidateSet('Error', 'PreserveParent', 'OverwriteParent')]
        [string]$CollisionAction = 'Error',
        [switch]$RemoveAfterReceive
    )

    $opSignal = [Signal]::Start('Complete-PlanPhaseTask', $Signal) | Select-Object -Last 1
    $receiveSignal = Receive-STBackgroundTask `
        -TaskId $TaskId `
        -Signal $opSignal `
        -Wait `
        -RemoveAfterReceive:$RemoveAfterReceive |
        Select-Object -Last 1
    $null = $opSignal.MergeSignal($receiveSignal)
    if (-not $receiveSignal.HasResult()) { return $opSignal }

    $received = $receiveSignal.GetResult()
    $envelope = $received.CompletionEnvelope
    if ($null -eq $envelope) {
        $null = $opSignal.LogCritical("Background phase task '$TaskId' did not return a completion envelope.")
        return $opSignal
    }

    $initializationSignal = ConvertFrom-STSignalRecord $envelope.InitializationSignal
    $workerSignal = ConvertFrom-STSignalRecord $envelope.WorkerSignal
    if ($null -ne $initializationSignal) { $null = $opSignal.MergeSignal($initializationSignal) }
    if ($null -ne $workerSignal) { $null = $opSignal.MergeSignal($workerSignal) }
    if ([bool]$envelope.Failed -or $opSignal.Failure()) {
        if (-not [string]::IsNullOrWhiteSpace([string]$envelope.Error)) {
            $null = $opSignal.LogCritical([string]$envelope.Error)
        }
        return $opSignal
    }

    $graph = $ItemSignal.GetPointer()
    if ($graph -isnot [Graph]) {
        $null = $opSignal.LogCritical('AwaitPhase ItemSignal does not have a Graph pointer.')
        return $opSignal
    }

    foreach ($record in @($workerSignal.GetResult().ExportedResults)) {
        $key = [string]$record.Key
        $shouldImport = $true
        if ($graph.Grid.Contains($key)) {
            switch ($CollisionAction) {
                'Error' {
                    $null = $opSignal.LogCritical("Cannot import background phase result '$key' because the parent graph already contains that key.")
                    return $opSignal
                }
                'PreserveParent' { $shouldImport = $false }
            }
        }
        if (-not $shouldImport) { continue }

        $importedSignal = [Signal]::Start([string]$record.Name, $ItemSignal) | Select-Object -Last 1
        if ($null -ne $record.Meta) { $importedSignal.SetMeta($record.Meta) }
        if ([bool]$record.HasResult) { $importedSignal.SetResult($record.Result) }
        $registerSignal = $graph.RegisterSignal($key, $importedSignal) | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($registerSignal)) { return $opSignal }
    }

    $opSignal.SetResult($received.Status)
    return $opSignal
}
