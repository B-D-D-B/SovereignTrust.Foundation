function Invoke-TokenEnvironment {
    [CmdletBinding()]
    param (
        [Conduit]$Conduit,
        [Conductor]$Conductor,
        [string]$Path,
        [object]$Plan  # Typically a small PSObject or Phase class in the future
    )

    if ($Conduit -and -not $Conduit.IsRunning) {
        throw "Conduction is not running. Cannot invoke Phase."
    }

    $opSignal = [Signal]::Start("Invoke-TokenEnvironment", $Conductor) | Select-Object -Last 1

    try {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            $opSignal.LogWarning("Path is empty. Nothing to resolve.")
            return $opSignal
        }

        if ($Path -is [string] -and $Path.StartsWith("Environment.")) {
            $Path = $Path.Substring("Environment.".Length)
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
            'process' { $value = [System.Environment]::GetEnvironmentVariable($key, 'Process') }
            'user'    { $value = [System.Environment]::GetEnvironmentVariable($key, 'User') }
            'machine' { $value = [System.Environment]::GetEnvironmentVariable($key, 'Machine') }
            default {
                # Try process → user → machine fallback
                $value = [System.Environment]::GetEnvironmentVariable($key, 'Process')
                if (-not $value) {
                    $value = [System.Environment]::GetEnvironmentVariable($key, 'User')
                }
                if (-not $value) {
                    $value = [System.Environment]::GetEnvironmentVariable($key, 'Machine')
                }
            }
        }

        if ($null -ne $value) {
            $opSignal.SetResult($value)
        }
        else {
            $opSignal.LogWarning("Environment variable not found for key: $Path")
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Invoke-TokenEnvironment: $_", $null, $_)
    }

    return $opSignal
}
