function Invoke-MappedAdapterCore {
    [CmdletBinding()]
    param (
        [Signal]$MappedAdapterSignal,
#        [Conduit]$Conduit,
#        [Conductor]$Conductor,
        [Signal]$ConductionSignal,
        [string]$Slot,
        [object]$Plan,  # Typically a small PSObject or Phase class in the future
        $Activity,
        $ItemSignal
    )

 #   if ( $Conduit -and -not $Conduit.IsRunning) {
 ##       throw "Conduction is not running. Cannot invoke Phase."
 #   }

    $opSignal = [Signal]::Start("Invoke-TokenConduction", $ConductionSignal) | Select-Object -Last 1

    $slotParts = $Slot -Split '\.'
    $slotParts = @($slotParts)
    try {
        $slotPathPart = $slotParts[0]
        $adapterPath = "*.#.$($slotPathPart).@"
        $adapterSignal = Resolve-PathFromDictionary -Dictionary $MappedAdapterSignal -Path $adapterPath -SignalLevel "Information" | Select-Object -Last 1
        if (-not $adapterSignal.HasResult())
        {
            $adapterPath = "%.*.#.$($slotPathPart).@"
            $adapterSignal = Resolve-PathFromDictionary -Dictionary $MappedAdapterSignal -Path $adapterPath | Select-Object -Last 1
        }
        
        if ($opSignal.MergeSignalAndVerifyFailure($adapterSignal)) {
            $opSignal.LogCritical("Adapter path '$adapterPath' not found in Conductor.")
            return $opSignal
        }
        
        $mappedSlotSignal = $adapterSignal.GetResultSignal()
        $resolvedAdapterSignal = Resolve-MappedAdapter `
            -AdapterSignal $mappedSlotSignal `
            -Signal $ConductionSignal `
            -ConductionContext $MappedAdapterSignal.GetJacket() `
        | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($resolvedAdapterSignal) -or -not $resolvedAdapterSignal.HasResult()) {
            return $opSignal
        }
        $adapter = $resolvedAdapterSignal.GetResult()
        
        $adapterIvokeSignal = $adapter.Invoke($Slot, $Activity, $ConductionSignal, $Plan, $ItemSignal) | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($adapterIvokeSignal)) {
            # Retain adapter-owned structured failure evidence without clearing failure.
            if ($adapterIvokeSignal.HasResult()) { $opSignal.SetResult($adapterIvokeSignal.GetResult()) }
            $opSignal.LogCritical("Adapter failed to resolve path '$Path' using slot '$Slot'.")
        }
        elseif (-not $adapterIvokeSignal.HasResult()) {
            $opSignal.LogInformation("Adapter did not return a result for slot '$Slot'.")
        }
        else {
            $opSignal.SetResult($adapterIvokeSignal.GetResult())
        }

    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Invoke-ConductionAdapter: $_", $null, $_)
    }

    return $opSignal}

