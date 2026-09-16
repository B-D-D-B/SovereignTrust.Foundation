function Invoke-ConductionAdapter {
    [CmdletBinding()]
    param (
        [Signal]$MappedAdapterSignal,
#        [Conduit]$Conduit,
        [Conductor]$Conductor,
        [Signal]$ConductionSignal,
        [string]$Slot,
        [object]$Plan,  # Typically a small PSObject or Phase class in the future
        $Activity,
        $ItemSignal
    )

 #   if ( $Conduit -and -not $Conduit.IsRunning) {
 ##       throw "Conduction is not running. Cannot invoke Phase."
 #   }

    $opSignal = [Signal]::Start("Invoke-TokenConduction", $Conductor) | Select-Object -Last 1

    $slotParts = $Slot -Split '\.'
    $slotParts = @($slotParts)
    try {
        $slotPathPart = $slotParts[0]
        $adapterPath = "*.#.$($slotPathPart).@"
        $adapterSignal = Resolve-PathFromDictionary -Dictionary $MappedAdapterSignal -Path $adapterPath | Select-Object -Last 1
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
            $opSignal.LogCritical("Adapter failed to resolve path '$Path' with slot '$Slot'.")
            return $opSignal
        }
        else {
            $opSignal.SetResult($adapterIvokeSignal.GetResult())
        }

    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Invoke-ConductionAdapter: $_", $null, $_)
    }

    return $opSignal}

