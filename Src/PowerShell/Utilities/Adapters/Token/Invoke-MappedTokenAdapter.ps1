function Invoke-MappedTokenAdapter {
    [CmdletBinding()]
    param (
        [MappedTokenAdapter]$MappedAdapter,
        [string]$Slot,
        # Conductor / environment signal that contains adapters (mapped attachments)
        [Parameter(Mandatory = $false)]
        [Signal]$Signal,

        [Parameter(Mandatory = $false)]
        [Signal]$ItemSignal,

        [object]$Plan,

        # Routing + IO parameters
        #        [Parameter(Mandatory = $false)]
        #        [string]$Adapter,

        [Parameter(Mandatory = $false)]
        [string]$Activity,


        [object]$Path
    )

    $opSignal = [Signal]::Start("Invoke-MappedTokenAdapter") | Select-Object -Last 1

    try {

        if (-not $Path) { $Path = $Plan.Path }

        if (-not $MappedAdapter) {
            return $opSignal.LogCritical("MappedAdapter is null.")
        }

        # If the Container and Resource is being passed through the token adapter, it should be used to set the path (the path will be used later by the memory generator to do a select)
        $ContainerSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Container" -SignalLevel "Information" | Select-Object -Last 1
        $ResourceSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Resource" -SignalLevel "Information" | Select-Object -Last 1

        if ($ContainerSignal.HasResult() -and $ResourceSignal.HasResult())
        {
            $Path = "Memory.$($ContainerSignal.GetResult()).$($ResourceSignal.GetResult())"
        }

        if (-not $Path -or -not ($Path -is [string])) {
            return $opSignal.LogCritical("Invalid or missing path: $Path")
        }

        # Remove enclosing [/] if present
        #$trimmed = $Path -replace '^\[\/|\]$', ''
        $trimmed = $Path -replace '^\[', '' -replace '\/\]$', ''

        # Split on period
        $parts = $trimmed -split '\.'

        if ($parts.Count -eq 0) {
            return $opSignal.LogWarning("No valid path parts found in: $Path")
        }

        $firstKey = $parts[0]

        # Look in the MappedAdapter Signal's graph for the corresponding key
        $graph = $MappedAdapter.Signal.GetPointer()
        $lookupPath = "#.$firstKey"

        $adapterSignal = Resolve-PathFromDictionary -Dictionary $graph -Path $lookupPath | Select-Object -Last 1
        $opSignal.MergeSignal($adapterSignal)

        if ($adapterSignal.Failure()) {
            return $opSignal.LogWarning("Could not resolve adapter for key: $firstKey")
        }

        $mappedSlotSignal = $adapterSignal.GetResultSignal()
        $resolvedAdapterSignal = Resolve-MappedAdapter `
            -AdapterSignal $mappedSlotSignal `
            -Signal $Signal `
            -ConductionContext $MappedAdapter.Signal.GetJacket() `
        | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($resolvedAdapterSignal) -or -not $resolvedAdapterSignal.HasResult()) {
            return $opSignal
        }
        $adapter = $resolvedAdapterSignal.GetResult()

#        while ($adapter -is [Signal]) {
#            $adapter = $adapter.GetResult()
#        }

        if ($adapter -and ($adapter | Get-Member -Name "Invoke")) {
            $TokenPlan = [PSCustomObject]@{
                Path = $trimmed
            }

            $configSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config" -SignalLevel "Information" | Select-Object -Last 1
            if ($configSignal.HasResult())
            {
                $null = Add-PathToDictionary -Dictionary $TokenPlan -Path "Config" -Value $configSignal.GetResult()
            }

            $invokeSignal = $adapter.Invoke($null, "Get", $Signal, $TokenPlan, $ItemSignal) | Select-Object -Last 1
            $opSignal.MergeSignal($invokeSignal)

            if ($invokeSignal.Success() -and $invokeSignal.HasResult()) {
                $result = $invokeSignal.GetResult()
                $opSignal.SetResult($result)
                $opSignal.LogInformation("✅ MappedTokenAdapter successfully invoked path: $trimmed to $result")
            }
            else {
                $opSignal.LogWarning("Invocation failed for path: $trimmed")
            }
        }
        else {
            $opSignal.LogWarning("Resolved adapter for '$firstKey' does not implement Invoke().")
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Invoke-MappedTokenAdapter: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}
8