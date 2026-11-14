
function Complete-Conduction {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Conduit]$Conduit
    )

    if (-not $Conduit.IsRunning) {
        Write-Warning "Conduction is already completed or was never started."
        return
    }

    try {
        # Finalize conduction
        $Conduit.CompleteConduction()

        # Optionally: Add a basic finalization log entry
        $finalizationEntry = [PSCustomObject]@{
            PhaseName = "ConductionComplete"
            Timestamp = (Get-Date)
        }
        $Conduit.Context.PhaseHistory += $finalizationEntry
    }
    catch {
        Write-Warning "Failed to complete Conduction: $_"
    }
}
