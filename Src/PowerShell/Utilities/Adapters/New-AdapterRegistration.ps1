function New-AdapterRegistration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Jacket,

        [Parameter(Mandatory)]
        [string]$Kind,

        [Parameter(Mandatory)]
        [string]$Slot,

        [object]$ConductionContext,

        [bool]$RetryFailedResolution = $false
    )

    return [PSCustomObject]@{
        PSTypeName            = 'SovereignTrust.AdapterRegistration'
        IsAdapterRegistration = $true
        Name                  = [string]$Slot
        Kind                  = [string]$Kind
        Slot                  = [string]$Slot
        Jacket                = $Jacket
        ConductionContext     = $ConductionContext
        State                 = 'Registered'
        Instance              = $null
        LastError             = $null
        RetryFailedResolution = $RetryFailedResolution
        SyncRoot              = [object]::new()
    }
}
