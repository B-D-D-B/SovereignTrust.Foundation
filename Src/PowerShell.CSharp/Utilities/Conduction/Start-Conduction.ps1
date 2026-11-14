
function Start-Conduction {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$WirePath,

        [Parameter()]
        [hashtable]$TransientTypeDictionary = @{},  # Optional injection for Phase realizations later

        [Parameter()]
        [hashtable]$SingletonTypeDictionary = @{}   # Optional singleton services later
    )

    # Load Jackets if needed - placeholder for now
    # (Later: load Wire/Jacket files into memory here)

    # Create the Conduit
    $conduit = [Conduit]::new()

    # Set up context (basic metadata)
    $conduit.Context.WirePath = $WirePath
    $conduit.Context.StartTime = (Get-Date)

    # (Optional) Engage transient/singleton type mappings
    if ($TransientTypeDictionary.Count -gt 0 -or $SingletonTypeDictionary.Count -gt 0) {
        $conduit.EngageConductor(
            $null,  # No full Conductor yet
            $TransientTypeDictionary,
            $SingletonTypeDictionary
        )
    }

    # Start the conduction lifecycle
    $conduit.StartConduction()

    # Return the ready Conduit to caller
    return $conduit
}
