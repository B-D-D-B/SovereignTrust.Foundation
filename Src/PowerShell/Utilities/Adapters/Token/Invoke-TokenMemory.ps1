function Invoke-TokenMemory {
    [CmdletBinding()]
    param (
        [MappedTokenAdapter]$MappedAdapter,
        [string]$Slot,
        # Conductor / environment signal that contains adapters (mapped attachments)
        [Parameter(Mandatory = $false)]
        [Signal]$Signal,

        [Parameter(Mandatory = $false)]
        [Signal]$ItemSignal,

        [object]$Plan,

        # Routing + IO parameters
        #        [Parameter(Mandatory = $false)]
        #        [string]$Adapter,

        [Parameter(Mandatory = $false)]
        [string]$Activity
    )

    $opSignal = [Signal]::Start("Invoke-TokenMemory", $ItemSignal) | Select-Object -Last 1

    try {
        $Key = $Plan.Path

        if ([string]::IsNullOrWhiteSpace($Key)) {
            $opSignal.LogWarning("Path is empty. Nothing to resolve.")
            return $opSignal
        }

        if ($Key -is [string] -and $Key.StartsWith("Memory.")) {
            $Key = $Key.Substring("Memory.".Length)
        }

        $segments = $Key -split '\.'

        $scope = 'Item'
        $path = $null

        if ($segments.Count -gt 1) {
            $scope = $segments[0]
            $path = ($segments[1..($segments.Count - 1)] -join '.')
        }
        else {
            $path = $segments[0]
        }

        $default = $null
        $dictionary = $null

        # Split path|default if present
        if ($path -and $path -like '*|*') {
            $parts = $path -split '\|', 2
            $path = $parts[0]
            $default = $parts[1]
        }

        # Alternate Delimeter to break into a default value
        if ($path -and $path -like '*=*') {
            $parts = $path -split '\=', 2
            $path = $parts[0]
            $default = $parts[1]
        }

        $pathSuffix = ""

        switch ($scope.ToLowerInvariant()) {
            'cache' {
                # Shortcut Path to cache items stored in the Conduction Signal
                $controlSignal = $Signal.GetControl($true)
                $dictionarySignal = Resolve-PathFromDictionary -Dictionary $controlSignal -Path "*.#" | Select-Object -Last 1
                if ($dictionarySignal.HasResult()) {
                    $dictionary = $dictionarySignal.GetResult()
                }

                # Cache items are always in their result
                $pathSuffix = ".@"
                $pathInner = ".@."

                break
            }
            'signal' {
                $dictionary = $Signal 
                break 
            }
            'control' {
                $dictionary = $Signal.GetControl($true)
                break 
            }
            <#
            'conduction' {
                $dictionary = $Signal 
                break 
            }
            'conductor' {
                $controlSignal = $Signal.GetControl($true)
                $dictionary = $controlSignal
                break 
            }#>
            'conduction' {
                $dictionary = $Signal
                break 
            }

            'adapters' {
                $dictionarySignal = Resolve-PathFromDictionary -Dictionary $Signal  -Path "*.#.Adapters.@.@.#" | Select-Object -Last 1
                if ($dictionarySignal.HasResult()) {
                    $dictionary = $dictionarySignal.GetResult()
                }
                break 
            }

            'generation' {
                # Shortcut Path to items created by Memory Generation
                $dictionarySignal = Resolve-PathFromDictionary -Dictionary $ItemSignal  -Path "*.#" | Select-Object -Last 1
                if ($dictionarySignal.HasResult()) {
                    $dictionary = $dictionarySignal.GetResult()
                }

                # Generation items are always in their result
                $pathSuffix = ".@"
                $pathInner = ".@."
                break 
            }
            'item' {
                $dictionary = $ItemSignal 
                break 
            }
            'plan' {
                $dictionary = $Plan 
                break 
            }
        }

        # Clear PathSuffix if path already contain it.
        if ($pathSuffix -and $path -like "*$pathSuffix*") {
            $pathSuffix = ""
        }
        elseif ($pathSuffix) {
            $delimeter = '.'

            # xpath conversion, the @ should be placed after the first block regardless of if it's a . or a ^ (This is perhaps a reason to infer XmlDocument for a node instead of using a ^ since a . in the path would conform.)
            if ($path -like "*^*") {
                $delimeter = '^'
            }

            $pathParts = $delimeter -eq '^' ? ($path -split '\^') : ($path -split '\.')

            if ($pathParts.Count -gt 1) {
                $path = $pathParts[0] + $pathInner + ($pathParts[1..($pathParts.Count - 1)] -join $delimeter)
            }
            else {
                $path = $path + $pathSuffix
            }
        }

            
        

        if ($null -ne $dictionary) {
            if (-not $path) {
                $opSlignal.SetResult($dictionary)
            }
            else {
                $valueSignal = Resolve-PathFromDictionary -Dictionary $dictionary -Path $path -Default $default -SignalLevel "Warning" | Select-Object -Last 1
                if ($opSignal.MergeSignalAndVerifyFailure($valueSignal)) {
                    return $opSignal
                }

                if ($valueSignal.HasResult()) {
                    $opSignal.SetResult($valueSignal.GetResult())
                }
            }
        }
        else {
            $opSignal.LogWarning("Memory variable not found for key: $Key")
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Invoke-TokenMemory: $_", $null, $_)
    }

    return $opSignal
}
