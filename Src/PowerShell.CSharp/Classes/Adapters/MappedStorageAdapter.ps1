<#
Class: MappedStorageAdapter
Purpose: Route a storage slot to its registered provider.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- Read: Retrieve content from a resource.
- Write: Store content in a resource.
- Delete: Remove a resource.
- Exists: Check whether a resource is present.
- List: Enumerate resource metadata with optional filter, type and sort.
ActivityValidation: OnInvoke, BeforeProviderResolution
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
#>
class MappedStorageAdapter {
    [SignalGraph.Signal]$Signal

    MappedStorageAdapter() {
        # Use static Start() instead
    }

    static [SignalGraph.Signal] Start([object]$Conductor) {
        $opSignal = [SignalGraph.Signal]::Start("MappedStorageAdapter.Start") | Select-Object -Last 1

        if (-not $Conductor) {
            $opSignal.LogCritical("Null Conductor passed to MappedStorageAdapter.Start()")
            return $opSignal
        }

        try {
            $adapter = [SovereignTrust.Foundation.Classes.Adapters.MappedStorageAdapter]::new()
            $adapter.Signal = [SignalGraph.Signal]::Start("MappedStorageAdapter") | Select-Object -Last 1
            $adapter.Signal.SetJacket($Conductor)
            $adapter.Signal.SetReversePointer($Conductor)

            $graphSignal = [SignalGraph.Graph]::Start("MappedStorageAdapter", $adapter, $false)
            $adapter.Signal.SetResult($graphSignal.GetResult())
            $adapter.Signal.SetPointer($graphSignal.GetResult())

            $opSignal.SetResult($adapter)
            $opSignal.LogInformation("✅ MappedStorageAdapter initialized.")
        }
        catch {
            $opSignal.LogCritical("💥 Exception in MappedStorageAdapter.Start(): $_", $null, $_.Exception)
        }

        return $opSignal
    }

    [SignalGraph.Signal] RegisterAdapter([object]$AdapterInstance, [string]$Key = "StorageService") {
        $opSignal = [SignalGraph.Signal]::Start("RegisterMappedAdapter:$Key") | Select-Object -Last 1
        if ($AdapterInstance -isnot [SignalGraph.Signal]) {
            $adapterSignal = [SignalGraph.Signal]::Start("Adapter:$Key") | Select-Object -Last 1
            $adapterSignal.SetResult($AdapterInstance)
        }
        else {
            $adapterSignal = $AdapterInstance
        }

        $graph = $this.Signal.GetPointer()
        $registeredAdapter = $adapterSignal.GetResult()
        if ([bool]$registeredAdapter.IsAdapterRegistration) {
            if ($registeredAdapter.Jacket -is [SignalGraph.Signal]) {
                $adapterSignal.SetJacket($registeredAdapter.Jacket)
            }
        }
        elseif ($null -ne $registeredAdapter.Signal) {
            $adapterSignal.SetJacket($registeredAdapter.Signal.GetJacket())
        }
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

    [SignalGraph.Signal] Invoke([object]$Context) {
        return $this.Invoke($null, $Context) | Select-Object -Last 1
    }

    [SignalGraph.Signal] Invoke([string]$Slot, [object]$Context) {
        return $this.Invoke($Slot, $Context) | Select-Object -Last 1
    }

    [SignalGraph.Signal]Invoke([string]$Slot, [string]$Activity, [SignalGraph.Signal]$ConductionSignal, [object]$Plan, [SignalGraph.Signal]$ItemSignal) {

        $opSignal = [SignalGraph.Signal]::Start("MappedStorageAdapter.Invoke:$Slot") | Select-Object -Last 1

        if ($Activity -notin @('Read', 'Write', 'Delete', 'Exists', 'List')) {
            $opSignal.LogCritical("Unsupported MappedStorageAdapter activity: '$Activity'.")
            return $opSignal
        }

        # TODO: Add Rule System for managing when multiple slots should be tried and if results should be aggregated or return on exists.

        $AdapterPath = "*.#.$Slot"
        $adapterSignal = Resolve-PathFromDictionary -Dictionary $this.Signal -Path $AdapterPath | Select-Object -Last 1

        $mappedSlotSignal = $adapterSignal.GetResultSignal()
        $resolvedAdapterSignal = Resolve-MappedAdapter `
            -AdapterSignal $mappedSlotSignal `
            -Signal $ConductionSignal `
            -ConductionContext $ConductionSignal `
        | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($resolvedAdapterSignal) -or -not $resolvedAdapterSignal.HasResult()) {
            return $opSignal
        }
        $adapter = $resolvedAdapterSignal.GetResult()
        
        $virtualPathSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.VirtualPath" -SignalLevel "Information" -Default $null | Select-Object -Last 1
        if (-not $virtualPathSignal.HasResult()) {
            $ResourceSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Resource" | Select-Object -Last 1
            $ContainerSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Container" | Select-Object -Last 1
            $Container = $ContainerSignal.HasResult() ? $ContainerSignal.GetResult() : $null
            $Name = $ResourceSignal.HasResult() ? $ResourceSignal.GetResult() : $null

            $virtualPath = ( @($Container, $Name) -join '/')
            Add-PathToDictionary -Dictionary $Plan -Path "VirtualPath" -Value $virtualPath 

        }

        $resultSignal = $adapter.Invoke($Slot, $Activity, $ConductionSignal, $Plan, $ItemSignal)

        if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)) {
            $opSignal.LogCritical("MappedStorageAdapter failed to invoke against slot '$Slot'.")
            return $opSignal
        }

        $opSignal.SetResult($resultSignal.GetResult())
        return $opSignal
    }
}

