
function Invoke-Conduction {
    [CmdletBinding()]
    param (
        [SignalGraph.Signal]$Signal,
        [SovereignTrust.Foundation.Classes.Conduction.Conductor]$Conductor,
        [SovereignTrust.Foundation.Classes.Conduction.Conduit]$Conduit,
        [object]$Phase  # Typically a small PSObject or Phase class in the future
        
    )

    if (-not $Conduit.IsRunning) {
        throw "Conduction is not running. Cannot invoke Phase."
    }

    try {
        # Execute the Phase inside the living Context
        $Conduit.ExecutePhase($Phase)
    }
    catch {
        Write-Warning "Failed to invoke Phase: $_"
    }
}
