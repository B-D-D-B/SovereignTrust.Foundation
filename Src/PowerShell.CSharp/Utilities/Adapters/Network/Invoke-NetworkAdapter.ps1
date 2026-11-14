function Invoke-NetworkAdapter {
    [CmdletBinding()]
    param (
        [Signal]$MappedAdapterSignal,
        [Conduit]$Conduit,
        [Conductor]$Conductor,
        [Signal]$ConductionSignal,
        [string]$Slot,
        [object]$Plan,  # Typically a small PSObject or Phase class in the future
        [Signal]$PlanSignal  # Typically a small PSObject or Phase class in the future
    )

    if ( $Conduit -and -not $Conduit.IsRunning) {
        throw "Conduction is not running. Cannot invoke Phase."
    }

    $opSignal = [Signal]::Start("Invoke-NetworkAdapter", $Conductor) | Select-Object -Last 1

    if ($null -eq $Plan)
    {
        $Plan = $PlanSignal.GetResult()
    }

    $action = $Plan.Action

    switch ($action) {
        "Start" {
            $AddressSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Addresses" | Select-Object -Last 1
            $ConductionPlanSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "ConductionPlan" | Select-Object -Last 1
            $MaxMessagesSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "MaxMessages" -SignalLevel "Warning" | Select-Object -Last 1
            $PollingIntervalSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "PollIntervalSeconds" -SignalLevel "Warning" | Select-Object -Last 1
            #$AddressSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Addresses" | Select-Object -Last 1

            $Address = $AddressSignal.GetResult()[0]
            $MaxMessages = $null
            $PollingInterval = $null
            
            if ($MaxMessagesSignal.HasResult())
            {
                $MaxMessages = $MaxMessagesSignal.GetResult()
            }
            
            if ($PollingIntervalSignal.HasResult())
            {
                $PollingInterval = $PollingIntervalSignal.GetResult()
            }
            
            Start-AzureStorageQueueListener -Conduit $Conduit -Conductor $Conductor -ConductionSignal $ConductionSignal -Address $Address -MaxMessages $MaxMessages -PollIntervalSeconds $PollingInterval -Plan $Plan -ListenerPlan $ConductionPlanSignal

            if ($current -is [Signal]) {
                $current = $current.Pointer
                $opSignal.LogVerbose("🔗 Dereferenced *Pointer")
                $processed = $true
                continue
            }
            else {
                $opSignal.LogWarning("Expected Signal for *Pointer, got $($current.GetType().Name)")
            }
        }
        "Result" {
            if ($current -is [Signal]) {
                $current = $current.Result
                $opSignal.LogVerbose("🎯 Dereferenced @Result")
                $processed = $true
                continue
            }
            else {
                $opSignal.LogWarning("Expected Signal for @Result, got $($current.GetType().Name)")
            }
        }
    }

    try {
        $adapterPath = "@.#.$Slot.@"
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
        
        $resolvedPathSignal = Resolve-PathWithExtensionFromPath -Signal $opSignal -Path $Path | Select-Object -Last 1
        
        if ($opSignal.MergeSignalAndVerifyFailure($resolvedPathSignal)) {
            $opSignal.LogCritical("Could not resolve path with extension for '$Path'.")
            return $opSignal
        } 
        
        $Path = $resolvedPathSignal.GetResult()

        $adapterIvokeSignal = $adapter.Invoke($ConductionSignal, $Plan) | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($adapterIvokeSignal)) {
            $opSignal.LogCritical("Adapter failed to resolve path '$Path' with slot '$Slot'.")
            return $opSignal
        }
        else {
            $opSignal.SetResult($adapterIvokeSignal.GetResult())
        }

    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Invoke-TokenStorage: $_", $null, $_)
    }

    return $opSignal}
