function Invoke-TokenDynamic {
    [CmdletBinding()]
    param (
        [MappedTokenAdapter]$MappedAdapter,
        [string]$Slot,

        [Parameter(Mandatory = $false)]
        [Signal]$Signal,

        [Parameter(Mandatory = $false)]
        [Signal]$ItemSignal,

        [object]$Plan,

        [Parameter(Mandatory = $false)]
        [string]$Activity
    )

    $opSignal = [Signal]::Start("Invoke-TokenDynamic", $ItemSignal) | Select-Object -Last 1

    try {
        # Path is ONLY the dynamic expression portion to translate
        # Prefer Plan.Path, else Plan.Key
        $path = $null
        if ($null -ne $Plan) {
            if ($null -ne $Plan.Path) { $path = [string]$Plan.Path }
            elseif ($null -ne $Plan.Key) { $path = [string]$Plan.Key }
        }

        # Allow "Dynamic.UtcNow(...)" as a convenience input
        if ($path.StartsWith("Dynamic.", [StringComparison]::OrdinalIgnoreCase)) {
            $path = $path.Substring("Dynamic.".Length)
        }

        if ([string]::IsNullOrWhiteSpace($path)) {
            $opSignal.LogWarning("Dynamic path is empty. Nothing to resolve.")
            return $opSignal
        }

        $valueSignal = Resolve-TokenDynamic `
            -Path $path `
            -MappedAdapter $MappedAdapter `
            -Signal $Signal `
            -ItemSignal $ItemSignal `
            -Plan $Plan

        if ($opSignal.MergeSignalAndVerifyFailure($valueSignal)) {
            return $opSignal
        }

        if ($valueSignal.HasResult()) {
            $opSignal.SetResult($valueSignal.GetResult())
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Invoke-TokenDynamic: $_", $null, $_)
    }

    return $opSignal
}
