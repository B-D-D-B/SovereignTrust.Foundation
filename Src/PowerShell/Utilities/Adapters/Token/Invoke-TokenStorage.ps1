function Invoke-TokenStorage {
    [CmdletBinding()]
    param (
        #[Conduit]$Conduit,
        [Signal]$Signal,
        [Signal]$ItemSignal,
        [string]$Path,
        [object]$Plan  # Typically a small PSObject or Phase class in the future
    )

    if ($Conduit -and -not $Conduit.IsRunning) {
        throw "Conduction is not running. Cannot invoke Phase."
    }

    $opSignal = [Signal]::Start("Invoke-TokenStorage", $Conductor) | Select-Object -Last 1


    try {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            $opSignal.LogWarning("Path is empty. Nothing to resolve.")
            return $opSignal
        }

        $segments = $Path -split '\.'
        $PartialPath = ($segments[2..($segments.Count - 1)] -join '.')
        $activity = $segments[2]

        $key = ''
        $scope = ''

        if ($segments.Count -eq 2) {
            $scope = $segments[0]
            $key = $segments[1]
        }
        else {
            $key = $segments[0]
        }

        $key = $segments[0]
        $slot = $segments[1]
        $value = $null

        $mappedAdapterPath = "%.*.#.Adapters.*.#.Mapped$key.@"
        $mappedAdapterSignal = Resolve-PathFromDictionary -Dictionary $Signal.GetControl($true) -Path $mappedAdapterPath | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($mappedAdapterSignal)) {
            $opSignal.LogCritical("MappedAdapter path '$mappedAdapterPath' not found in Conductor.")
            return $opSignal
        }

        $mappedAdapter = $mappedAdapterSignal.GetResult()

        #This was sending PartialPath as the activity, but it needs to just be the first part and we need to route the rest as virtual path in the plan.

        $resultSignal = $mappedAdapter.Invoke($slot, $activity, $Signal, $Plan, $ItemSignal) | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)) {
            $opSignal.LogCritical("MappedAdapter failed to resolve key '$key' with scope '$scope'.")
            return $opSignal
        }
        else {
            $value = $resultSignal.GetResult()
        }

        if ($null -ne $value) {
            $opSignal.SetResult($value)
        }
        else {
            $opSignal.LogWarning("Storage variable not found for key: $Path")
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Invoke-TokenStorage: $_", $null, $_)
    }

    return $opSignal
}
