<#
Class: MappedDataAdapter
Purpose: Route a data slot through Invoke-MappedAdapterCore.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- Write: Run a data write operation.
- Query: Read data.
- Delete: Remove data.
- Admin: Run an administration command.
- WriteItem: Write one data item.
- WriteBatch: Write a batch of data items.
- OpenCanonical: Open a canonical artifact record.
- CaptureWriter: Capture a writer's artifact baseline.
- ReadCaptured: Read a captured baseline.
- PublishWriter: Publish a writer's candidate.
- CreateEntry: Create an entry from a draft capture.
- OpenArtifactProcess: Open an artifact process report.
- InspectArtifactParts: Inspect artifact parts.
- StartArtifactGeneration: Start generation of an artifact part.
- PublishArtifactCandidate: Publish a generated artifact candidate.
- FailArtifactGeneration: Mark artifact generation as failed.
- CompleteArtifactGeneration: Complete published artifact generation.
- RetryRejectedPart: Retry a rejected artifact part.
- IngestArtifactPart: Ingest an artifact part.
- ReconcileDelivery: Reconcile delivery state.
- ResumeDelivery: Resume a pending delivery.
- RetireDelivery: Retire a verified delivery.
- RepairUnpublished: Repair an unpublished artifact.
- SaveArtifactProcess: Save an artifact process snapshot.
- SyncArtifactProcess: Synchronize an artifact process.
- ReconcileArtifactProcess: Reconcile an artifact process.
ActivityValidation: OnInvoke, BeforeProviderResolution
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
ActivityForwarding: Canonical
#>

class MappedDataAdapter {
    [Signal]$Signal

    MappedDataAdapter() {
        # Use static Start() instead
    }

    static [Signal] Start([object]$Conductor) {
        $opSignal = [Signal]::Start("MappedDataAdapter.Start") | Select-Object -Last 1

        if (-not $Conductor) {
            $opSignal.LogCritical("Null Conductor passed to MappedDataAdapter.Start()")
            return $opSignal
        }

        try {
            $adapter = [MappedDataAdapter]::new()
            $adapter.Signal = [Signal]::Start("MappedDataAdapter") | Select-Object -Last 1
            $adapter.Signal.SetJacket($Conductor)
            $adapter.Signal.SetReversePointer($Conductor)

            $graphSignal = [Graph]::Start("MappedDataAdapter", $adapter, $false)
            $adapter.Signal.SetPointer($graphSignal.GetResult())

            $opSignal.SetResult($adapter)
            $opSignal.LogInformation("✅ MappedDataAdapter initialized.")
        }
        catch {
            $opSignal.LogCritical("💥 Exception in MappedDataAdapter.Start(): $_", $null, $_)
        }

        return $opSignal
    }

    [Signal] RegisterAdapter([object]$AdapterInstance, [string]$Key = "QueueService") {
        $opSignal = [Signal]::Start("RegisterMappedAdapter:$Key") | Select-Object -Last 1
        if ($AdapterInstance -isnot [Signal]) {
            $adapterSignal = [Signal]::Start("Adapter:$Key") | Select-Object -Last 1
            $adapterSignal.SetResult($AdapterInstance)
        }
        else {
            $adapterSignal = $AdapterInstance
        }

        $AddMappedAdapterSignal = Add-PathToDictionary -Dictionary $AdapterInstance -Path "MappedAdapter" -Value $this | Select-Object -Last 1
        $graph = $this.Signal.GetPointer()
        $registerSignal = $graph.RegisterSignal($Key, $adapterSignal)
        $opSignal.MergeSignal($registerSignal)

        if ($registerSignal.Success()) {
            $opSignal.LogInformation("✅ Registered adapter at key: '$Key'")
        } else {
            $opSignal.LogWarning("Failed to register adapter at key: '$Key'")
        }

        $this.Signal.MergeSignal($opSignal)
        return $opSignal
    }

    [Signal] Invoke([string]$Slot, [string]$Activity, [Signal]$ConductionSignal, [object]$Plan, [Signal]$ItemSignal) {
        $opSignal = [Signal]::Start("MappedDataAdapter.Invoke:$Slot") | Select-Object -Last 1

        $allowedActivities = @(
            'Write', 'Query', 'Delete', 'Admin', 'WriteItem', 'WriteBatch',
            'OpenCanonical', 'CaptureWriter', 'ReadCaptured', 'PublishWriter',
            'CreateEntry', 'OpenArtifactProcess', 'InspectArtifactParts',
            'StartArtifactGeneration', 'PublishArtifactCandidate',
            'FailArtifactGeneration', 'CompleteArtifactGeneration',
            'RetryRejectedPart', 'IngestArtifactPart', 'ReconcileDelivery',
            'ResumeDelivery', 'RetireDelivery', 'RepairUnpublished',
            'SaveArtifactProcess', 'SyncArtifactProcess', 'ReconcileArtifactProcess'
        )
        if ($Activity -notin $allowedActivities) {
            $opSignal.LogCritical("Unsupported MappedDataAdapter activity: '$Activity'.")
            return $opSignal
        }
        foreach ($allowedActivity in $allowedActivities) {
            if ($Activity -eq $allowedActivity) { $Activity = $allowedActivity; break }
        }

        $resultSignal = Invoke-MappedAdapterCore -MappedAdapterSignal $this.Signal -ConductionSignal $ConductionSignal -Slot $Slot -Activity $Activity -Plan $Plan -ItemSignal $ItemSignal | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)){
            if ($resultSignal.HasResult()) { $opSignal.SetResult($resultSignal.GetResult()) }
            return $opSignal
        }

        $opSignal.SetResult($resultSignal.GetResult($true))
        return $opSignal
    }
}
