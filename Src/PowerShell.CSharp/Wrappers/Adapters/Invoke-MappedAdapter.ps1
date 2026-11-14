function Invoke-MappedAdapter {
    [CmdletBinding()]
    param (
        # Conductor / environment signal that contains adapters (mapped attachments)

        [Parameter(Mandatory = $false)]
        [Signal]$Signal,

        [Parameter(Mandatory = $false)]
        [Signal]$ItemSignal,

        [object]$Plan,

        # Routing + IO parameters
        [Parameter(Mandatory = $false)]
        [string]$Adapter,

        [Parameter(Mandatory = $false)]
        [string]$Activity,

#        [Parameter(Mandatory = $false)]
#        [string]$VirtualPath,

 #       [Parameter(Mandatory = $false)]
 #       [string]$Container,

        [Parameter(Mandatory = $false)]
        [string]$Name = $null
        )

        #Write-Host "abc"
    # ░▒▓█ SIGNAL START █▓▒░
    $opSignal = [Signal]::Start("Invoke-StorageAdapter", $Signal) | Select-Object -Last 1
        #Write-Host "def"

    try {

        # Resolve the mapped storage adapter instance from the passed $Signal (Conductor Signal Jacket)
        # Adapter string is expected to be the mapped adapter name (e.g., "Storage.Content", "MappedStorage", etc.)
        # Convention: adapters live under something like: %.*.#.Adapters.*.#.<AdapterName>

        $adapterParts = $Adapter -split '\.'

        $adapterName     = $adapterParts.Count -ge 1 ? $adapterParts[0] : $null
        $adapterSlot     = $adapterParts.Count -ge 2 ? $adapterParts[1] : $null

        $adapterPath = "%.*.#.Adapters.*.#.Mapped$adapterName"
        $adapterSignal = Resolve-PathFromDictionary -Dictionary ($Signal.GetControl($true)) -Path $adapterPath | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure($adapterSignal)) {
            $opSignal.LogCritical("Cannot resolve storage adapter '$Adapter' from signal (path: $adapterPath).")
            return $opSignal
        }

        $mappedAdapter = $adapterSignal.GetResult($true)

        if ($null -eq $mappedAdapter) {
            $opSignal.LogCritical("Resolved storage adapter '$Adapter' is null.")
            return $opSignal
        }

        <#
        # Build an item signal for the adapter invoke call (keeps contract similar to other adapters/condensers)
        # NOTE: Uses Add-PathToDictionary for mutations to stay doctrine-compliant.
        $itemJacketSignal = [Signal]::Start("StorageAdapter.Item") | Select-Object -Last 1
        $VirtualPath = $null -eq $VirtualPath -or $VirtualPath -eq "" ? ( @($Container, $Name) -join '/') : $VirtualPath
        $item = @{
            VirtualPath = $VirtualPath
        }

        $itemSignal = [Signal]::Start("StorageAdapter.Item") | Select-Object -Last 1
        $itemSignal.SetResult($item)
#>

       # $itemJacketSignal.SetJacket($ItemSignal)

        # ░▒▓█ Invoke the resolved storage adapter █▓▒░
        # Contract: .Invoke($opSignal, $Signal, $ItemSignal)
        $invokeSignal = $mappedAdapter.Invoke($adapterSlot, $Activity, $Signal, $Plan, $ItemSignal) | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($invokeSignal)) {
            if ($invokeSignal.HasResult()) { $opSignal.SetResult($invokeSignal.GetResult()) }
            $opSignal.LogCritical("Storage adapter invoke failed (Adapter: $Adapter).")
            return $opSignal
        }

        if ($invokeSignal.HasResult()) {
             $opSignal.SetResult($invokeSignal.GetResult())
        }
    }
    catch {
        $opSignal.LogCritical("Exception during storage adapter invoke: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}
