class Storage_EmbeddedFileSystem {
    [MappedStorageAdapter]$MappedAdapter
    [Signal]$Signal
    #[object]$Jacket

    Storage_EmbeddedFileSystem() {
    }

    Storage_EmbeddedFileSystem([MappedStorageAdapter]$mappedAdapter) {
        $this.MappedAdapter = $mappedAdapter
    }

    [Signal] Construct([object]$dictionary) {
        $opSignal = [Signal]::Start("Construct-EmbeddedFileSystem") | Select-Object -Last 1

        try {
            if ($null -eq $dictionary) {
                return $opSignal.LogCritical("Cannot construct EmbeddedFileSystem — provided dictionary is null.")
            }

            $this.Signal = [Signal]::Start("Construct-EmbeddedFileSystem") | Select-Object -Last 1

            $jacket = [Signal]::Start("Construct-EmbeddedFileSystem") | Select-Object -Last 1 
            
            $this.Signal.SetJacket($jacket)
            $jacket.SetResult($dictionary)
            $opSignal.LogInformation("EmbeddedFileSystem constructed successfully with provided jacket.")
        }
        catch {
            $opSignal.LogCritical("Error constructing EmbeddedFileSystem: $_")
        }

        return $opSignal
    }

    [Signal] ReadObjectAsJsonDEAD([string]$virtualPath) {
        $opSignal = [Signal]::Start("EmbeddedFileSystem.ReadObjectAsJson") | Select-Object -Last 1

        try {
            # 🧠 Ensure the virtual path ends with '.json'
            if (-not $virtualPath.ToLower().EndsWith(".json")) {
                $virtualPath = "$virtualPath.json"
            }

            # 🔁 Read raw content using internal ReadObject
            $rawSignal = $this.ReadObject($virtualPath) | Select-Object -Last 1
            $opSignal.MergeSignal($rawSignal)

            if ($rawSignal.Success()) {
                $jsonText = $rawSignal.GetResult()
                $parsed = $null

                try {
                    $parsed = $jsonText | ConvertFrom-Json -Depth 20
                }
                catch {
                    return $opSignal.LogCritical("Failed to parse JSON content: $($_.Exception.Message)", $null, $_)
                }

                $opSignal.SetResult($parsed)
                $opSignal.LogInformation("JSON content parsed successfully from: $virtualPath")
            }
            else {
                $opSignal.LogWarning("No raw content found at: $virtualPath")
            }
        }
        catch {
            $opSignal.LogCritical("Exception in EmbeddedFileSystem.ReadObjectAsJson: $($_.Exception.Message)", $null, $_)
        }

        return $opSignal
    }

    [Signal] ReadObjectDEAD([string]$virtualPath) {
        $opSignal = [Signal]::Start("EmbeddedFileSystem.ReadObject:$virtualPath") | Select-Object -Last 1

        try {
            # ░▒▓█ RESOLVE ADDRESSES FROM %.@.Addresses █▓▒░
            $addressSignal = Resolve-PathFromDictionary -Dictionary $this -Path '%.@.Addresses' | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure(@($addressSignal))) {
                return $opSignal.LogCritical("Could not resolve Jacket.Addresses path.")
            }

            $callSignal = Invoke-EmbeddedFileSystem_ReadObject -Signal $this.Signal -VirtualPath $virtualPath -Addresses $addressSignal.GetResult() | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifySuccess($callSignal)) {
                $opSignal.SetResult($callSignal.GetResult())
                $opSignal.LogInformation("Successfully read object from virtual path: $virtualPath")   
            }
        }
        catch {
            $opSignal.LogCritical("Exception in EmbeddedFileSystem.ReadObject: $($_.Exception.Message)", $null, $_)
        }

        return $opSignal
    }

    [Signal]Invoke([string]$Slot, [string]$Activity, [Signal]$ConductionSignal, [object]$Plan, [Signal]$ItemSignal) {
        $virtualPathSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "VirtualPath" | Select-Object -Last 1
        $virtualPath = $virtualPathSignal.GetResult()
        $opSignal = [Signal]::Start("EmbeddedFileSystem.$slot.$activity.$virtualPath") | Select-Object -Last 1

        try {
            # ░▒▓█ RESOLVE ADDRESSES FROM %.@.Addresses █▓▒░
            $addressSignal = Resolve-PathFromDictionary -Dictionary $this -Path '$.%.@.Addresses' | Select-Object -Last 1
            $signalLevelSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path 'Config.SignalLevel' -Default "Critical" | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure(@($addressSignal))) {
                return $opSignal.LogCritical("Could not resolve Jacket.Addresses path.")
            }`

            $callSignal = $null
            switch ($activity) {
                "Read" {
                    $callSignal = Invoke-EmbeddedFileSystem_ReadObject `
                        -Signal $this.Signal `
                        -VirtualPath $virtualPath `
                        -SignalLevel $signalLevelSignal.GetResult() `
                        -Addresses @($addressSignal.GetResult()) |
                    Select-Object -Last 1

                    # TODO: Move to Storage Adapter so it works across implementations. 5-17-26
                    if ($callSignal.Failure()) {
                        $contentSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Content" -SignalLevel "Warning" | Select-Object -Last 1
                        if ($contentSignal.HasResult()) {
                            $content = $contentSignal.GetResult()

                            $saveIfNewSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.SaveIfNew" -Default $false -SignalLevel "Warning" | Select-Object -Last 1
                            if ($saveIfNewSignal.GetResult()) {
                                $clonePlan = (Resolve-ClonePlan -Plan $Plan | Select-Object -Last 1).GetResult()
                                $null = Add-PathToDictionary -Dictionary $clonePlan -Path "Config.Content" -Value $content
                                $writeResultSignal = $this.Invoke($Slot, "Write", $ConductionSignal, $clonePlan, $ItemSignal)
                                if ($opSignal.MergeSignalAndVerifyFailure($writeResultSignal)) {
                                    return $opSignal
                                }
                            }

                            if ($content -is [PSCustomObject]) {
                                $content = $content | ConvertTo-Json -Depth 100
                            }

                            $callSignal.LogRecovery("Default Content Override")
                            $callSignal.SetResult($content)
                        }    
                    }

                    break
                }

                "Write" {
                    $contentSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Content" | Select-Object -Last 1
                    $content = $contentSignal.GetResult()

                    $callSignal = Invoke-EmbeddedFileSystem_WriteObject `
                        -Signal $this.Signal `
                        -Content $content `
                        -VirtualPath $virtualPath `
                        -Addresses @($addressSignal.GetResult()) |
                    Select-Object -Last 1
                    break
                }

                "Delete" {
                    $callSignal = Invoke-EmbeddedFileSystem_DeleteObject `
                        -Signal $this.Signal `
                        -VirtualPath $virtualPath `
                        -Addresses @($addressSignal.GetResult()) |
                    Select-Object -Last 1
                    break
                }

                default {
                    $opSignal.LogCritical("Unsupported adapter activity '$activity'.")
                    return $opSignal
                }
            }

            if ($opSignal.MergeSignalAndVerifySuccess($callSignal) -and $callSignal.HasResult()) {
                $opSignal.SetResult($callSignal.GetResult())
                $opSignal.LogInformation("Successfully completed '$activity' for virtual path: $virtualPath")
            }
        }
        catch {
            $opSignal.LogCritical("Exception in EmbeddedFileSystem.Invoke: $($_.Exception.Message)", $null, $_)
        }

        return $opSignal
    }

    [Signal] InvokeDEAD([string]$virtualPath, [object]$Plan) {
        $opSignal = [Signal]::Start("EmbeddedFileSystem.ReadObject:$virtualPath") | Select-Object -Last 1

        try {
            # ░▒▓█ RESOLVE ADDRESSES FROM %.@.Addresses █▓▒░
            $addressSignal = Resolve-PathFromDictionary -Dictionary $this -Path '$.%.@.Addresses' | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure(@($addressSignal))) {
                return $opSignal.LogCritical("Could not resolve Jacket.Addresses path.")
            }

            $callSignal = Invoke-EmbeddedFileSystem_ReadObject -Signal $this.Signal -VirtualPath $virtualPath -Addresses $addressSignal.GetResult() | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifySuccess($callSignal)) {
                $opSignal.SetResult($callSignal.GetResult())
                $opSignal.LogInformation("Successfully read object from virtual path: $virtualPath")   
            }
        }
        catch {
            $opSignal.LogCritical("Exception in EmbeddedFileSystem.ReadObject: $($_.Exception.Message)", $null, $_)
        }

        return $opSignal
    }
}
