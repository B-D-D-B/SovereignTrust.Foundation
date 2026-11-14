function Invoke-MappedStorageAdapterWrapper {
    [CmdletBinding()]
    param (
        [Signal]$OpSignal = $null,
        [object]$Signal
    )

    # ░▒▓█ SIGNAL START █▓▒░
    $opSignal = $OpSignal ??  [Signal]::Start("Invoke-ConductionCondenser") | Select-Object -Last 1

    try {
        # ░▒▓█ VALIDATE INPUT █▓▒░
        $Config = $Signal.GetResult()

        if ($null -eq $Config) {
            $opSignal.LogCritical("Config is null. Cannot proceed.")
            return $opSignal
        }

        $consdenserPath = "%.*.#.MappedCondenserAdapter.@.#.ConductionCondenser"
        $consdenserSignal = Resolve-PathFromDictionary -Dictionary $Signal -Path $adapterPath | Select-Object -Last 1

        $consdenser = $adapterSignal.GetResult()
        
        # TODO: Place the check for if this should be done in an isolated run
        # ░▒▓█ Run the Conduction Condenser using the Config bits  █▓▒░
        $consdenserIvokeSignal = $consdenser.Invoke($Slot, $ConductionSignal, $Plan) | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($consdenserIvokeSignal)) {
            $opSignal.LogCritical("Conduction consdenser failed.")
            return $opSignal
        }
        else {
            $opSignal.SetResult($consdenserIvokeSignal.GetResult())
        }

    }
    catch {
        $opSignal.LogCritical("Exception during conduction condenser run: $($_.Exception.Message)", $null, $_)
    }

            return $opSignal

}