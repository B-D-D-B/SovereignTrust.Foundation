<#
Class: Token_Storage
Purpose: Resolve storage token values.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- Get: Resolve a token value from the requested path.
ActivityValidation: OnInvoke, BeforeDispatch
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
#>
class Token_Storage {
    [Signal]$Signal
    [Conductor]$Conductor
    [MappedTokenAdapter]$MappedAdapter
    [object]$Jacket

    Token_Storage() {
    }

    static [Token_Storage] Start([MappedTokenAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [Token_Storage]::new()
        $instance.MappedAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("GraphCondenser")
        return $instance
    }

    [Signal] Construct([object]$dictionary) {
        $opSignal = [Signal]::Start("Construct-EmbeddedFileSystem") | Select-Object -Last 1

        try {
            if ($null -eq $dictionary) {
                return $opSignal.LogCritical("Cannot construct EmbeddedFileSystem — provided dictionary is null.")
            }

            $this.Jacket = $dictionary
            $opSignal.LogInformation("EmbeddedFileSystem constructed successfully with provided jacket.")
        }
        catch {
            $opSignal.LogCritical("Error constructing EmbeddedFileSystem: $_")
        }

        return $opSignal
    }

    [Signal] Invoke([string]$Slot, [string]$Activity, $ConductionSignal, $Plan, $ItemSignal) {
        $opSignal = [Signal]::Start("Token_Storage.Invoke") | Select-Object -Last 1

        if ($Activity -notin @('Get')) {
            $opSignal.LogCritical("Unsupported Token_Storage activity: '$Activity'.")
            return $opSignal
        }

        try {
            $Path = $Plan.Path

            # Resolve existing VirtualPath from $Plan (sovereign read)
            $virtualPathSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.VirtualPath" -SignalLevel "Information" | Select-Object -Last 1

            # If VirtualPath is missing/empty, set it via sovereign write
            if (-not $virtualPathSignal.HasResult() -or -not $virtualPathSignal.GetResult())
            {
                $null = Add-PathToDictionary -Dictionary $Plan -Path "Config.VirtualPath" -Value $Path
            }
            
            $resultSignal = Invoke-TokenStorage -Signal $ConductionSignal -ItemSignal $ItemSignal -Path $Path -Plan $Plan | Select-Object -Last 1
            $opSignal.MergeSignal($resultSignal)

            if ($resultSignal.HasResult()) {
                $opSignal.SetResult($resultSignal.GetResult())
                $opSignal.LogInformation("✅ Token storage path '$Path' resolved successfully.")
            }   
            else {
                $opSignal.LogWarning("Token storage path '$Path' failed to resolve.")
            }
        }
        catch {
            $opSignal.LogCritical("🔥 Exception in Token_Storage.Invoke: $($_.Exception.Message)", $null, $_)
        }

        return $opSignal
    }
}
