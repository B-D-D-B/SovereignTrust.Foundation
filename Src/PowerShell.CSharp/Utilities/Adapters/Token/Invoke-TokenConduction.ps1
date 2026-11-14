function Invoke-TokenConduction {
    [CmdletBinding()]
    param (
        [Conduit]$Conduit,
        [Conductor]$Conductor,
        [object]$Path,
        [object]$Plan  # Typically a small PSObject or Phase class in the future
    )

    if ($Conduit -and -not $Conduit.IsRunning) {
        throw "Conduction is not running. Cannot invoke Phase."
    }

    $opSignal = [Signal]::Start("Invoke-TokenConduction", $Conductor) | Select-Object -Last 1

    try {
        if ($null -eq $Path) {
            $opSignal.LogWarning("Path is empty. Nothing to resolve.")
            return $opSignal
        }

        $segments = $Path -split '\.'

        $key = ''
        $scope = ''

        if ($segments.Count -eq 2) {
            $scope = $segments[0]
            $key = $segments[1]
        }
        else {
            $key = $segments[0]
        }

        $value = $null

        switch ($scope.ToLowerInvariant()) {
            'process' { $value = [System.Conduction]::GetConductionVariable($key, 'Process') }
            'user'    { $value = [System.Conduction]::GetConductionVariable($key, 'User') }
            'machine' { $value = [System.Conduction]::GetConductionVariable($key, 'Machine') }
            default {
                # Try process → user → machine fallback
                $value = [System.Conduction]::GetConductionVariable($key, 'Process')
                if (-not $value) {
                    $value = [System.Conduction]::GetConductionVariable($key, 'User')
                }
                if (-not $value) {
                    $value = [System.Conduction]::GetConductionVariable($key, 'Machine')
                }
            }
        }

        if ($null -ne $value) {
            $opSignal.SetResult($value)
            $opSignal.MarkSuccess()
        }
        else {
            $opSignal.LogWarning("Conduction variable not found for key: $Path")
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Invoke-TokenConduction: $_", $null, $_)
    }

    return $opSignal
}
