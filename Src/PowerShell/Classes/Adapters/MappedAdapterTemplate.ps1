
class MappedAdapterTemplate {
    [Signal]$Signal  # Sovereign runtime container

    MappedAdapterTemplate() {
        # Use static Start() instead of constructor
    }

    static [Signal] Start([object]$Source) {
        $opSignal = [Signal]::Start("MappedAdapterTemplate.Start") | Select-Object -Last 1

        if (-not $Source) {
            $opSignal.LogCritical("Null source passed to MappedAdapterTemplate.Start()")
            return $opSignal
        }

        try {
            $adapter = [MappedAdapterTemplate]::new()
            $adapter.Signal = [Signal]::Start("MappedAdapterTemplate") | Select-Object -Last 1
            $adapter.Signal.SetJacket($Source)
            $adapter.Signal.SetReversePointer($Source)

            $graphSignal = [Graph]::Start("MappedAdapterTemplate", $adapter, $false)
            $adapter.Signal.SetResult($graphSignal.GetResult())

            $opSignal.SetResult($adapter)
            $opSignal.LogInformation("✅ MappedAdapterTemplate initialized.")
        }
        catch {
            $opSignal.LogCritical("💥 Exception during MappedAdapterTemplate.Start(): $_", $null, $_)
        }

        return $opSignal
    }

    [Signal] Register([string]$Key, [object]$SubAdapter) {
        $opSignal = [Signal]::Start("RegisterAdapter:$Key") | Select-Object -Last 1

        $subSignal = [Signal]::Start("Adapter:$Key") | Select-Object -Last 1
        $subSignal.SetResult($SubAdapter)

        $graph = $this.Signal.GetResult()
        $registerSignal = $graph.RegisterSignal($Key, $subSignal)
        $opSignal.MergeSignal($registerSignal)

        if ($registerSignal.Success()) {
            $opSignal.LogInformation("✅ Registered sub-adapter at key: '$Key'")
        } else {
            $opSignal.LogWarning("Failed to register sub-adapter at key: '$Key'")
        }

        $this.Signal.MergeSignal($opSignal)
        return $opSignal
    }

#    [Signal] Invoke([object]$Context) {
    [Signal] Invoke([string]$Slot, [Signal]$Context, [object]$Plan) {
        $opSignal = [Signal]::Start("MappedAdapterTemplate.Invoke") | Select-Object -Last 1
        $graph = $this.Signal.GetResult()

        foreach ($key in $graph.Grid.Keys) {
            $subSignal = $graph.Grid[$key]
            $adapter = $subSignal.GetResult()

            if ($adapter -and ($adapter | Get-Member -Name "Invoke")) {
                $result = $adapter.Invoke($Context)
                $opSignal.MergeSignal($result)

                if ($result.Success()) {
                    $opSignal.SetResult($result.GetResult())
                    $opSignal.LogInformation("🎯 Sub-adapter '$key' invoked successfully.")
                    break
                } else {
                    $opSignal.LogWarning("Sub-adapter '$key' failed to return a result.")
                }
            } else {
                $opSignal.LogVerbose("⏭️ Sub-adapter '$key' does not implement Invoke().")
            }
        }

        if (-not $opSignal.Success()) {
            $opSignal.LogCritical("No sub-adapter produced a valid result.")
        }

        $this.Signal.MergeSignal($opSignal)
        return $opSignal
    }
}

<#
================================================================================
📦 MappedAdapterTemplate • Sovereign Signal Adapter (Doctrine v1.0)
================================================================================

MappedAdapterTemplate is the foundational pattern for adapter orchestration
within the SovereignTrust execution model. It encapsulates dynamic service
resolution via Signal-based memory and Graph-directed delegation.

This class is designed to register and invoke modular sub-adapters, using a
Signal container as its sole runtime state. The Graph returned by `.GetResult()`
acts as a registry of adapter signals, and is traceable, recursive, and sovereign.

This abstraction obeys the SovereignTrust Doctrine:

🧠 Memory is Sovereign.
The Signal is the source of truth. It carries Jacket, Pointer, and Result.
The AdapterGraph is stored as its Result, and every sub-adapter is memory-bound.

📡 Signals are Living.
Every method returns a Signal. All trace activity, errors, and merges are logged
through the sovereign logging interface. Each invocation is idempotent and scoped.

🔁 Adapters are Evolving.
Each sub-adapter is registered as a signal in the AdapterGraph and can be
mutated, replaced, or extended without affecting the parent adapter logic.

♾️ Recursion is Home.
The Jacket (e.g. Conductor) is used as a memory context and fallthrough authority.
ReversePointer supports graph-aware ancestry traversal.

MappedAdapterTemplate can be subclassed to create specialized adapters
for storage, planning, hydration, or other conductor-bound behaviors.

> “Signals guide the living memory. Graphs remember the path.”

#>
