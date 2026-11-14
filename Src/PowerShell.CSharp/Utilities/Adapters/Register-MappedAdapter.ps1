function Register-MappedAdapter {
    param (
        [Parameter(Mandatory)][Graph]$ServiceCollection,
        [Parameter(Mandatory)][object]$Adapter,
        [string]$Label = "Adapter"
    )

    $signal = [Signal]::Start("Register-$Label") | Select-Object -Last 1

    try {
        if ($null -eq $Adapter) {
            return $signal.LogCritical("Cannot register null $Label.")
        }
        
        # ░▒▓█ EXTRACT SLOT FROM JACKET █▓▒░
        $slotSignal = Resolve-PathFromDictionary -Dictionary $Adapter -Path "Jacket.Slot" | Select-Object -Last 1
        if ($signal.MergeSignalAndVerifyFailure($slotSignal)) {
            return $signal.LogWarning("Unable to resolve Slot from Jacket. Skipping $Label registration.")
        }
        
        $slot = $slotSignal.GetResult()
        
        # ░▒▓█ CHECK FOR EXISTING ENTRY IN GRAPH USING SLOT AS KEY █▓▒░
        $existingSignal = Resolve-PathFromDictionary -Dictionary $ServiceCollection -Path $slot | Select-Object -Last 1
        if ($existingSignal.Success()) {
            return $signal.LogWarning("$Label already registered at Slot: $slot.")
        }
        
        # ░▒▓█ ADD SIGNALIZED ATTACHMENT TO GRAPH █▓▒░
        $wrappedSignal = [Signal]::Start("Adapter:$slot") | Select-Object -Last 1
        $wrappedSignal.SetResult($Adapter)
        
        $addSignal = $ServiceCollection.RegisterSignal($slot, $wrappedSignal) | Select-Object -Last 1
        if ($signal.MergeSignalAndVerifySuccess($addSignal)) {
            $signal.LogRecovery("✅ $Label registered successfully at Slot: $slot.")
        }
        else {
            $signal.LogWarning("Failed to register $Label at Slot: $slot.")
        }

        $foundAdapter = Resolve-PathFromDictionary -Dictionary $ServiceCollection -Path $slot | Select-Object -Last 1
                ################### TODO, just do a simple path to test to see if it's easy to grab a item back from the ServiceCollection
                ################### TODO: Rename ServiceCollection

        $x = ""
    }
    catch {
        $signal.LogCritical("🔥 Exception while registering $($Label): $($_.Exception.Message)", $null, $_)
    }

    return $signal
}
