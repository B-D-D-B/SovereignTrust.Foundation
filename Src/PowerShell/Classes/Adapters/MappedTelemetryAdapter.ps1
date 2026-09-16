class MappedTelemetryAdapter {
    [Signal]$Signal

    MappedTelemetryAdapter() {
        # Use static Start() instead
    }

    static [Signal] Start([object]$Conductor) {
        $opSignal = [Signal]::Start("MappedTelemetryAdapter.Start") | Select-Object -Last 1

        if (-not $Conductor) {
            $opSignal.LogCritical("Null Conductor passed to MappedTelemetryAdapter.Start()")
            return $opSignal
        }

        try {
            $adapter = [MappedTelemetryAdapter]::new()
            $adapter.Signal = [Signal]::Start("MappedTelemetryAdapter") | Select-Object -Last 1

            # Yes, this is a weird place to keep the Conductor, we played around with putting it in the Signal, 
            # but now we know it should be in Grid of the Signal or just include a $Conductor in the adapter
            $adapter.Signal.SetJacket($Conductor)
            $adapter.Signal.SetReversePointer($Conductor)

            $graphSignal = [Graph]::Start("MappedTelemetryAdapter", $adapter, $false)
            $adapter.Signal.SetPointer($graphSignal)

            $opSignal.SetResult($adapter)
            $opSignal.LogInformation("✅ MappedTelemetryAdapter initialized.")
        }
        catch {
            $opSignal.LogCritical("💥 Exception in MappedTelemetryAdapter.Start(): $_", $null, $_)
        }

        return $opSignal
    }

    [Signal] RegisterAdapter([object]$AdapterInstance, [string]$Key = "StorageService") {
        $opSignal = [Signal]::Start("RegisterMappedAdapter:$Key") | Select-Object -Last 1
        $adapterSignal = [Signal]::Start("Adapter:$Key") | Select-Object -Last 1
        $adapterSignal.SetResult($AdapterInstance)

        $graph = $this.Signal.GetResult()
        $registerSignal = $graph.RegisterSignal($Key, $adapterSignal)
        $opSignal.MergeSignal($registerSignal)

        if ($registerSignal.Success()) {
            $opSignal.LogInformation("✅ Registered adapter at key: '$Key'")
        }
        else {
            $opSignal.LogWarning("Failed to register adapter at key: '$Key'")
        }

        $this.Signal.MergeSignal($opSignal)
        return $opSignal
    }

    [Signal] Invoke([object]$Path) {
        $opSignal = [Signal]::Start("MappedTelemetryAdapter.Invoke") | Select-Object -Last 1

        try {
            # Yes, this is a weird place to keep the Conductor, we played around with putting it in the Signal, 
            # but now we know it should be in Grid of the Signal or just include a $Conductor in the adapter
            $resultSignal = Invoke-MappedTelemetryAdapter -MappedAdapter $this -Path $Path | Select-Object -Last 1
            $opSignal.MergeSignal($resultSignal)

            if ($resultSignal.Success()) {
                $opSignal.SetResult($resultSignal.GetResult())
                $result = $resultSignal.GetResult()
                $opSignal.LogInformation("✅ MappedTelemetryAdapter resolved path successfully: $Path -> $result")
            }
            else {
                $opSignal.LogWarning("MappedTelemetryAdapter failed to resolve path: $Path")
            }
        }
        catch {
            $opSignal.LogCritical("🔥 Exception in MappedTelemetryAdapter.Invoke: $($_.Exception.Message)", $null, $_)
        }

        return $opSignal
    }

    [Signal] InvokeAdapterMethod([string]$MethodName, [object[]]$Args) {
        $opSignal = [Signal]::Start("MappedTelemetryAdapter.Invoke:$MethodName") | Select-Object -Last 1
        $graph = $this.Signal.GetResult()

        foreach ($key in $graph.Grid.Keys) {
            $adapterSignal = $graph.Grid[$key]
            $resolvedAdapterSignal = Resolve-MappedAdapter `
                -AdapterSignal $adapterSignal `
                -Signal $this.Signal `
                -ConductionContext $this.Signal.GetJacket() `
            | Select-Object -Last 1
            if ($resolvedAdapterSignal.Failure() -or -not $resolvedAdapterSignal.HasResult()) { continue }
            $adapter = $resolvedAdapterSignal.GetResult()

            if ($null -ne $adapter -and ($adapter | Get-Member -Name $MethodName)) {
                $result = $adapter.InvokeMethod($MethodName, $Args)
                $opSignal.MergeSignal($result)

                if ($result.Success()) {
                    $opSignal.SetResult($result.GetResult())
                    $opSignal.LogInformation("🎯 Adapter '$key' successfully invoked '$MethodName'")
                    break
                }
                else {
                    $opSignal.LogWarning("Adapter '$key' failed on method '$MethodName'")
                }
            }
            else {
                $opSignal.LogVerbose("⏭️ Adapter '$key' does not implement '$MethodName'")
            }
        }

        if (-not $opSignal.Success()) {
            $opSignal.LogCritical("No adapter succeeded for method '$MethodName'")
        }

        $this.Signal.MergeSignal($opSignal)
        return $opSignal
    }
}

<#
================================================================================
📦 MappedTelemetryAdapter • AI Trainer Block (Doctrine v1.0)
================================================================================

MappedTelemetryAdapter is the sovereign abstraction layer for accessing
memory-bearing storage services. It is responsible for routing all storage
requests — such as loading JSON, XML, text, deleting files, or listing folders —
through a signal-aware fallback mechanism across all registered services.

This abstraction obeys the SovereignTrust Doctrine:

🧠 Memory is Sovereign.
Storage is not assumed. Each request resolves through the memory space 
of attached services, each carrying its own jacket, slot, and lineage.

📡 Signals are Living.
All operations return Signals — traceable, mergeable, and idempotent.
Failures are not silent. All fallback is logged and lineage-aware.

🔁 Adapters are Evolving.
Each registered service is a dynamic adapter. Services can be replaced,
mutated, or upgraded without altering the conduction flow above.

♾️ Recursion is Home.
This object can defer to its owning Conductor. The Conductor can fall back
to its HostConductor. Together, they form the recursive memory fabric that
bootstraps Sovereign execution.

MappedTelemetryAdapter enables runtime access to all sovereign plans,
templates, modules, and data — using only memory and WirePath.

> “When memory becomes sovereign, storage becomes signal.”

#>
