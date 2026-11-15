<#
Class: MappedConduitAdapter
Purpose: Try registered conduits until Invoke(Context, Plan) succeeds.
ActivityScope: None
Activities: None; Invoke takes context and plan without an Activity argument.
#>

class MappedConduitAdapter {
    [SignalGraph.Signal]$Signal

    MappedConduitAdapter() {
        # Use static Start() to initialize
    }

    static [SignalGraph.Signal] Start() {
        return [SignalGraph.Signal]::Start($null)
    }

    static [SignalGraph.Signal] Start([object]$conductor) {
        $opSignal = [SignalGraph.Signal]::Start("MappedConduitAdapter.Start") | Select-Object -Last 1

        if (-not $conductor) {
            $opSignal.LogCritical("Null Conductor passed to Start().")
            return $opSignal
        }

        try {
            $adapter = [SovereignTrust.Foundation.Classes.Adapters.MappedConduitAdapter]::new()
            $adapter.Signal = [SignalGraph.Signal]::Start("MappedConduitAdapter") | Select-Object -Last 1
            $adapter.Signal.SetJacket($conductor)
            $adapter.Signal.SetReversePointer($conductor)

            $graphSignal = [SignalGraph.Graph]::Start("MappedConduitAdapter", $adapter, $false)
            $adapter.Signal.SetResult($graphSignal, $true)
            $adapter.Signal.SetPointer($graphSignal.GetResult()) 

            $opSignal.SetResult($adapter)
            $opSignal.LogInformation("✅ MappedConduitAdapter initialized successfully.")
        }
        catch {
            $opSignal.LogCritical("💥 Exception during adapter setup: $_", $null, $_.Exception)
        }

        return $opSignal
    }

    [SignalGraph.Signal] RegisterAdapter([object]$ConduitAdapter, [string]$Key) {
        $opSignal = [SignalGraph.Signal]::Start("RegisterMappedAdapter:$Key") | Select-Object -Last 1
        $adapterSignal = [SignalGraph.Signal]::Start("Adapter:$Key") | Select-Object -Last 1
        $adapterSignal.SetResult($ConduitAdapter)

        $graph = $this.Signal.GetResult() | Select-Object -Last 1
        $registerSignal = $graph.RegisterSignal($Key, $adapterSignal)
        $opSignal.MergeSignal($registerSignal)

        if ($registerSignal.Success()) {
            $opSignal.LogInformation("✅ Registered Conduit adapter under key: '$Key'")
        } else {
            $opSignal.LogWarning("Failed to register adapter at key: '$Key'")
        }

        $this.Signal.MergeSignal($opSignal)
        return $opSignal
    }

    [SignalGraph.Signal] Invoke([object]$Context, [object]$Plan) {
        $opSignal = [SignalGraph.Signal]::Start("MappedConduitAdapter.Invoke") | Select-Object -Last 1
        $graph = $this.Signal.GetResult() | Select-Object -Last 1

        foreach ($key in $graph.Grid.Keys) {
            $subSignal = $graph.Grid[$key]
            $resolvedAdapterSignal = Resolve-MappedAdapter `
                -AdapterSignal $subSignal `
                -Signal $this.Signal `
                -ConductionContext $this.Signal.GetJacket() `
            | Select-Object -Last 1
            if ($resolvedAdapterSignal.Failure() -or -not $resolvedAdapterSignal.HasResult()) { continue }
            $adapter = $resolvedAdapterSignal.GetResult()

            if ($null -ne $adapter -and ($adapter | Get-Member -Name "Invoke")) {
                $resultSignal = $adapter.Invoke($Context, $Plan) | Select-Object -Last 1
                $opSignal.MergeSignal($resultSignal)

                if ($resultSignal.Success()) {
                    $opSignal.SetResult($resultSignal, $true)
                    $opSignal.LogInformation("🎯 Adapter '$key' invoked successfully.")
                    break
                } else {
                    $opSignal.LogWarning("Adapter '$key' failed to produce a result.")
                }
            } else {
                $opSignal.LogVerbose("⏭️ Adapter '$key' does not support Invoke().")
            }
        }

        if (-not $opSignal.Success()) {
            $opSignal.LogCritical("No Conduit adapter produced a valid result.")
        }

        $this.Signal.MergeSignal($opSignal)
        return $opSignal
    }
}
