function Invoke-MappedAdapter-Obsolete {
    [CmdletBinding()]
    param (
        [Signal]$Signal,
        [Conductor]$Conductor
    )

    $opSignal = [Signal]::Start("Invoke-MappedAdapter", $Signal) | Select-Object -Last 1

    $jacket = $Signal.GetJacket()

    if ($null -ne $jacket) {
        $nameSignal = Resolve-PathFromDictionary -Dictionary $jacket -Path "@.Name" | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifySuccess($nameSignal)) {
            $name = $nameSignal.GetResult()

            $jacketSignal = $jacket

            $settingsSignal = Resolve-PathFromDictionary -Dictionary $jacket -Path "@.Settings" -SignalLevel "Warning" | Select-Object -Last 1
            if ($settingsSignal.Success() -and $settingsSignal.HasResult())
            {
                #$virtualPathSignal = Resolve-PathFromDictionary -Dictionary $settingsSignal -Path "@.VirtualPath" -SignalLevel "Warning" | Select-Object -Last 1
                
                $commandsSignal = Resolve-PathFromDictionary -Dictionary $settingsSignal -Path "@.Commands" | Select-Object -Last 1
                if ($commandsSignal.Success()) {
                    $commands = $commandsSignal.GetResult()
                    $commandCount = $commands.Count
                    $opSignal.LogVerbose("Jacket '$name' contains $commandCount commands.")


                    foreach ($command in $commands) {
                        $commandSignal = [Signal]::Start("Invoke-MappedAdapter", $Signal) | Select-Object -Last 1
                        $commandSignal.SetResult($command) | Out-Null

                        $conductorSignal = [Signal]::Start("Invoke-MappedAdapter", $Signal) | Select-Object -Last 1
                        $conductorSignal.SetResult($Conductor) | Out-Null
                        
                        $commandSignal.SetJacket($conductorSignal) | Out-Null
                        $commandJacketSignal = [Signal]::Start("Invoke-MappedAdapter", $commandSignal) | Select-Object -Last 1
                        $commandJacketSignal.SetJacket($commandSignal) | Out-Null
                        
                        $invokeFabCondenserSignal = Invoke-MappedAdapter -Signal $commandJacketSignal -Conductor $Conductor | Select-Object -Last 1
                        $opSignal.MergeSignal($invokeFabCondenserSignal)
                    }

                }
                else {
                    $opSignal.LogVerbose("Jacket '$name' contains no adapters.")
                }
            }
            else {

                $conductorSignal = [Signal]::Start("Invoke-MappedAdapter", $Signal) | Select-Object -Last 1
                $conductorSignal.SetJacket($Conductor.Signal) | Out-Null

                $virtualPathSignal = Resolve-PathFromDictionary -Dictionary $jacket -Path "@.VirtualPath" | Select-Object -Last 1
                if ($opSignal.MergeSignalAndVerifyFailure($virtualPathSignal)) {
                    return $opSignal.LogCritical("❌ Jacket does not contain a resolvable 'VirtualPath' path.")

                }

                $virtualPathParts = $virtualPathSignal.GetResult() -split "\."

                $mappedAdapterPath = "$.*.#.Adapters.*.#.Mapped$($virtualPathParts[0])"
                $slot = $virtualPathParts[1]

                $adapterSignal = Resolve-PathFromDictionary -Dictionary $Conductor -Path $mappedAdapterPath | Select-Object -Last 1
                if ($opSignal.MergeSignalAndVerifyFailure($adapterSignal)) {
                    $opSignal.LogCritical("❌ MappedAdapter not found at path '$mappedAdapterPath'. Ensure the Conductor has been initialized with the MappedAdapter.")
                    return $opSignal
                }

                $adapter = $adapterSignal.GetResult() | Select-Object -Last 1
                while ($adapter -is [Signal]) {
                    $adapter = $adapter.GetResult()
                }

                $invokeSignal = $adapter.Invoke($slot, $jacket, $jacket) | Select-Object -Last 1

                if ($opSignal.MergeSignalAndVerifySuccess($invokeSignal)) {
                    $opSignal.LogInformation("Adapter '$name' invoked successfully.")
                    $opSignal.SetResult($invokeSignal.GetResult()) | Out-Null
                }
                else {
                    $opSignal.LogWarning("Adapter '$name' failed invocation.")
                }
            }
        }
    }
    else {
        $opSignal.LogWarning("Null jacket encountered during iteration — skipping.")
    }

    return $opSignal
}