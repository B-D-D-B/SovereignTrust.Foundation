
<#
Class: ProcessCondenser
Purpose: Run one bounded native process and capture binary output.
Activities: Run
#>
class ProcessCondenser {
    [SignalGraph.Signal]$Signal

    static [ProcessCondenser] Start([SovereignTrust.Foundation.Classes.Adapters.MappedCondenserAdapter]$mappedAdapter, [SovereignTrust.Foundation.Classes.Conduction.Conductor]$conductor) {
        $instance = [ProcessCondenser]::new()
        $instance.Signal = [SignalGraph.Signal]::Start('ProcessCondenser.Control') | Select-Object -Last 1
        return $instance
    }

    [SignalGraph.Signal] Invoke([string]$Slot, [string]$Activity, [SignalGraph.Signal]$ConductionSignal, [object]$Plan, [SignalGraph.Signal]$ItemSignal) {
        $opSignal = [SignalGraph.Signal]::Start('ProcessCondenser.Invoke', $ItemSignal) | Select-Object -Last 1
        if ($Activity -cne 'Run') {
            $null = $opSignal.LogCritical('Unsupported ProcessCondenser activity.')
            return $opSignal
        }
        try {
            $result = Invoke-ProcessCondenserCore -Plan $Plan
            $null = $opSignal.SetResult($result)
        }
        catch {
            $message = if ($_.Exception.Message -like 'Process cleanup uncertain*') { $_.Exception.Message } else { "Process invocation failed: $($_.Exception.Message)" }
            $null = $opSignal.LogCritical($message, $null, $_.Exception)
        }
        return $opSignal
    }
}
