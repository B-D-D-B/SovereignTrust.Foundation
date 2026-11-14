function Invoke-TransformCondenserCore {
    [CmdletBinding()]
    param (
        [Conduit]$Conduit,
        [Conductor]$Conductor,
        [string]$Path,
        [object]$Plan  # Typically a small PSObject or Phase class in the future
    )

    if ($Conduit -and -not $Conduit.IsRunning) {
        throw "Conduction is not running. Cannot invoke Formatter Phase."
    }

    $opSignal = [Signal]::Start("Invoke-TransformCondenser", $Conductor) | Select-Object -Last 1

    try {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            $opSignal.LogWarning("Formatter path is empty.")
            return $opSignal
        }

        # Formatter.XYZ.Path → get 'XYZ'
        $segments = $Path -split '\.'
        if ($segments.Count -lt 2) {
            $opSignal.LogCritical("Invalid Formatter path: '$Path'")
            return $opSignal
        }

        $formatterKey = $segments[1]
        $subInvokeName = "Invoke-TransformCondenser$formatterKey"

        if (-not (Get-Command $subInvokeName -ErrorAction SilentlyContinue)) {
            $opSignal.LogCritical("Formatter handler '$subInvokeName' not found.")
            return $opSignal
        }

        # Call the sub-formatter function
        $subSignal = & $subInvokeName -Path $Path -Plan $Plan | Select-Object -Last 1

        $opSignal.MergeSignal($subSignal)
        if ($subSignal.Success()) {
            $opSignal.SetResult($subSignal.GetResult())
            $opSignal.LogInformation("✅ Formatter '$formatterKey' resolved successfully.")
        } else {
            $opSignal.LogWarning("Formatter '$formatterKey' failed to resolve.")
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Invoke-TokenFormatter: $_", $null, $_)
    }

    return $opSignal
}
