<#
This function takes a pointer and a json document and returns the point in the document. 
#>
function Invoke-TokenJsonNavigator {
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

    $opSignal = [Signal]::Start("Invoke-TokenNavigator", $Conductor) | Select-Object -Last 1

    try {
        if ([string]::IsNullOrWhiteSpace($Path)) {
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
            'process' { $value = [System.Navigator]::GetNavigatorVariable($key, 'Process') }
            'user'    { $value = [System.Navigator]::GetNavigatorVariable($key, 'User') }
            'machine' { $value = [System.Navigator]::GetNavigatorVariable($key, 'Machine') }
            default {
                # Try process → user → machine fallback
                $value = [System.Navigator]::GetNavigatorVariable($key, 'Process')
                if (-not $value) {
                    $value = [System.Navigator]::GetNavigatorVariable($key, 'User')
                }
                if (-not $value) {
                    $value = [System.Navigator]::GetNavigatorVariable($key, 'Machine')
                }
            }
        }

        if ($null -ne $value) {
            $opSignal.SetResult($value)
            $opSignal.MarkSuccess()
        }
        else {
            $opSignal.LogWarning("Navigator variable not found for key: $Path")
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Invoke-TokenNavigator: $_", $null, $_)
    }

    return $opSignal
}
