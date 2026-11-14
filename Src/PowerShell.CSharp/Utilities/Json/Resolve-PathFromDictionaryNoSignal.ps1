function Resolve-PathFromDictionaryNoSignal {
    param (
        [Parameter(Mandatory)] $Dictionary,
        [string]$Path,
        [bool]$IgnoreInternalObjects = $true,
        [string]$InternalObjectsPrefix = "_",
        [bool]$AssumeInteralObjects = $false
    )

        if ($null -eq $Path) 
        { 
            return $null
        }

    $parts = $Path -split '\.'
    $current = $Dictionary

    foreach ($part in $parts) {
        if ($null -eq $current) { return $null }

        if ($IgnoreInternalObjects) {
            if ($current -is [hashtable]) {
                foreach ($key in @($current.Keys)) {
                    if ($key.StartsWith($InternalObjectsPrefix)) {
                        #$current.Remove($key)
                    }
                }
            }
            elseif ($current -is [pscustomobject]) {
                foreach ($prop in @($current.PSObject.Properties)) {
                    if ($prop.Name.StartsWith($InternalObjectsPrefix)) {
                        if ($AssumeInteralObjects) {
                            $propName = $prop.Name
                            $current = $current.$propName
                        }
                        else {
                            #$current.PSObject.Properties.Remove($prop.Name)                            
                        }
                    }
                }
            }
        }

        if ($null -eq $current) 
        { 
            return $null
        }

        # Traverse dictionary
        if ($current -is [System.Collections.IDictionary] -and $current.Contains($part)) {
            $current = $current[$part]
        }
        # Traverse hashtable
        elseif ($current -is [hashtable]) {
            if ($current.Contains($part)) {
                $current = $current[$part]
            }
            else {
                return $null
            }
        }
        # Traverse pscustomobject..
        elseif ($current -is [pscustomobject]) {
            if ($current.PSObject.Properties.Name -contains $part) {
                $current = $current.$part
            }
            else {
                return $null
            }
        }
        # Traverse enumerable (array-like) by matching Name property
        elseif ($current -is [System.Collections.IEnumerable] -and -not ($current -is [string])) {
            $found = $null
            foreach ($item in $current) {
                if (($item -is [pscustomobject] -or $item -is [hashtable]) -and `
                    ($item.Name -eq $part)) {
                    $found = $item
                    break
                }
            }
            if ($found) {
                $current = $found
            }
            else {
                return $null
            }
        }



        # Traverse PowerShell class instance
        elseif ($current.GetType().IsClass -and $current.GetType().Namespace -ne "System") {
            $propInfo = $current.GetType().GetProperty($part)
            if ($null -eq $propInfo) {
                throw "Class $($current.GetType().Name) does not have a property named '$part'."
            }

            $next = $propInfo.GetValue($current, $null)
            if ($null -eq $next) {
                return $null
            }

            $current = $next
        }
        else {
            return $null
        }
    }

    return $current
}
