# ================================
# 📦 MergeCondenser.ps1 (patched)
# ================================
function Invoke-MergeJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Base,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Overlay,

        [ValidateSet('Replace','Union','Concat','Merge')]
        [string]$MergeArrayHandling = 'Replace',

        [ValidateSet('Ignore','Merge')]
        [string]$MergeNullValueHandling = 'Ignore',

        [int]$Depth = 50
    )

    $opSignal = [Signal]::Start("Merge-JsonObjects") | Select-Object -Last 1

    try {
        if (-not ('Newtonsoft.Json.Linq.JToken' -as [type])) {
            Add-Type -AssemblyName 'Newtonsoft.Json' -ErrorAction Stop
        }

        $settings = [Newtonsoft.Json.Linq.JsonMergeSettings]::new()
        $settings.MergeNullValueHandling = [Newtonsoft.Json.Linq.MergeNullValueHandling]$MergeNullValueHandling
        $settings.MergeArrayHandling     = [Newtonsoft.Json.Linq.MergeArrayHandling]$MergeArrayHandling

        $baseJson    = if ($Base    -is [string]) { $Base }    else { $Base    | ConvertTo-Json -Depth $Depth }
        $baseToken    = [Newtonsoft.Json.Linq.JToken]::Parse($baseJson)

        $overlayJson = if ($Overlay -is [string]) { $Overlay } else { $Overlay | ConvertTo-Json -Depth $Depth }
        $overlayToken = [Newtonsoft.Json.Linq.JToken]::Parse($overlayJson)

        $result = $baseToken.DeepClone()
        $result.Merge($overlayToken, $settings)

        $opSignal.SetResult(($result.ToString() | ConvertFrom-Json -Depth $Depth))

        $opSignal.LogInformation("✅ Merge completed successfully (Array=$MergeArrayHandling, Nulls=$MergeNullValueHandling).")
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Merge-JsonObjects: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}

function Invoke-ConvertToUnifiedHashtable {
    param (
        [Parameter(Mandatory)][object]$InputObject
    )

    $signal = [Signal]::Start("Invoke-ConvertToUnifiedHashtable") | Select-Object -Last 1

    function Convert-Node {
        param([object]$node)

        # Unwrap Signal -> Result
        if ($node -is [Signal]) {
            $node = $node.GetResult()
        }

        if ($null -eq $node) { return $null }

        # Graph -> use Grid as the working memory dictionary
        if ($node -is [Graph]) {
            $node = $node.Grid
        }

        # Strings are IEnumerable; treat as scalar
        if ($node -is [string]) { return $node }

        # Dictionary-like -> OrderedDictionary recursively
        if ($node -is [System.Collections.IDictionary]) {
            $od = [ordered]@{}
            foreach ($k in $node.Keys) {
                $od[$k] = Convert-Node $node[$k]
            }
            return $od
        }

        # Arrays / lists -> normalize each element
        if ($node -is [System.Collections.IEnumerable] -and $node -isnot [string]) {
            # Avoid treating PSCustomObject as IEnumerable (it usually isn't, but keep guard)
            if ($node -is [pscustomobject]) {
                # fall through to PSObject.Properties
            }
            else {
                $arr = @()
                foreach ($item in $node) {
                    $arr += ,(Convert-Node $item)
                }
                return $arr
            }
        }

        # PSCustomObject / class: use properties
        try {
            $props = $node.PSObject.Properties
            if ($null -eq $props -or $props.Count -eq 0) {
                # Scalar / leaf object
                return $node
            }

            $od = [ordered]@{}
            foreach ($p in $props) {
                $od[$p.Name] = Convert-Node $p.Value
            }
            return $od
        }
        catch {
            # Fallback: treat as scalar
            return $node
        }
    }

    try {
        $converted = Convert-Node $InputObject
        if ($converted -isnot [System.Collections.IDictionary]) {
            # Ensure the top-level result is dictionary-ish (your merge expects it)
            $converted = [ordered]@{ Value = $converted }
            $signal.LogWarning("Input normalized to scalar; wrapped in ordered dictionary under key 'Value'.")
        }

        $signal.SetResult($converted)
        $signal.LogInformation("✅ Object normalized to unified ordered dictionary (recursive).")
    }
    catch {
        $signal.LogCritical("Failed to convert object to unified ordered dictionary: $($_.Exception.Message)")
    }

    return $signal
}

function Invoke-TransformCondenserDictionaries {
    param (
        [Parameter(Mandatory)][System.Collections.IDictionary]$Base,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Overlay,

        [ValidateSet('Replace','Concat','Union')]
        [string]$ArrayHandling = 'Replace',

        [ValidateSet('Ignore','Merge')]
        [string]$NullHandling = 'Ignore',

        [bool]$Recursive = $true,
        [bool]$CloneBase = $true
    )

    $signal = [Signal]::Start("Invoke-TransformCondenserDictionaries") | Select-Object -Last 1

    function Clone-Dict {
        param([System.Collections.IDictionary]$d)

        $clone = [ordered]@{}
        foreach ($k in $d.Keys) {
            $v = $d[$k]
            if ($v -is [System.Collections.IDictionary]) {
                $clone[$k] = Clone-Dict $v
            }
            elseif ($v -is [System.Collections.IEnumerable] -and $v -isnot [string]) {
                # shallow clone arrays; nested objects already unified by converter
                $arr = @()
                foreach ($i in $v) { $arr += ,$i }
                $clone[$k] = $arr
            }
            else {
                $clone[$k] = $v
            }
        }
        return $clone
    }

    function Merge-Arrays {
        param($left, $right)

        switch ($ArrayHandling) {
            'Replace' { return $right }
            'Concat'  { return @($left) + @($right) }
            'Union'   {
                # Union by value stringification (simple + predictable for JSON-like usage)
                $seen = [System.Collections.Generic.HashSet[string]]::new()
                $out = @()
                foreach ($x in @($left) + @($right)) {
                    $key = if ($null -eq $x) { '<null>' } else { $x | ConvertTo-Json -Depth 10 -Compress }
                    if ($seen.Add($key)) { $out += ,$x }
                }
                return $out
            }
        }
    }

    function Merge-Inner {
        param(
            [System.Collections.IDictionary]$target,
            [System.Collections.IDictionary]$source
        )

        foreach ($key in $source.Keys) {
            $srcVal = $source[$key]

            # Null handling
            if ($null -eq $srcVal -and $NullHandling -eq 'Ignore') {
                continue
            }

            if ($target.Contains($key)) {
                $dstVal = $target[$key]

                if ($Recursive -and ($dstVal -is [System.Collections.IDictionary]) -and ($srcVal -is [System.Collections.IDictionary])) {
                    Merge-Inner -target $dstVal -source $srcVal
                    continue
                }

                if (($dstVal -is [System.Collections.IEnumerable] -and $dstVal -isnot [string]) -and
                    ($srcVal -is [System.Collections.IEnumerable] -and $srcVal -isnot [string]) -and
                    ($dstVal -isnot [System.Collections.IDictionary]) -and
                    ($srcVal -isnot [System.Collections.IDictionary])) {

                    $target[$key] = Merge-Arrays -left $dstVal -right $srcVal
                    continue
                }

                # Scalar or type mismatch: overlay wins
                $target[$key] = $srcVal
            }
            else {
                $target[$key] = $srcVal
            }
        }
    }

    try {
        $working = if ($CloneBase) { Clone-Dict $Base } else { $Base }
        Merge-Inner -target $working -source $Overlay

        $signal.SetResult($working)
        $signal.LogInformation("✅ Dictionary merge completed successfully (Recursive=$Recursive, ArrayHandling=$ArrayHandling, NullHandling=$NullHandling, CloneBase=$CloneBase).")
    }
    catch {
        $signal.LogCritical("🔥 Exception in Invoke-TransformCondenserDictionaries: $($_.Exception.Message)", $null, $_)
    }

    return $signal
}

function Invoke-TransformCondenserUnifiedMemory {
    param (
        [Parameter(Mandatory)][object]$Base,
        [Parameter(Mandatory)][object]$Overlay,

        [ValidateSet('Replace','Concat','Union')]
        [string]$ArrayHandling = 'Replace',

        [ValidateSet('Ignore','Merge')]
        [string]$NullHandling = 'Ignore',

        [bool]$Recursive = $true,
        [bool]$CloneBase = $true
    )

    $signal = [Signal]::Start("Invoke-TransformCondenserUnifiedMemory") | Select-Object -Last 1

    try {
        $baseHash    = Invoke-ConvertToUnifiedHashtable -InputObject $Base   | Select-Object -Last 1
        $overlayHash = Invoke-ConvertToUnifiedHashtable -InputObject $Overlay | Select-Object -Last 1

        if ($signal.MergeSignalAndVerifyFailure(@($baseHash, $overlayHash))) {
            $signal.LogCritical("Failed to normalize base/overlay into unified memory dictionaries.")
            return $signal
        }

        $mergeSignal = Invoke-TransformCondenserDictionaries `
            -Base ($baseHash.GetResult()) `
            -Overlay ($overlayHash.GetResult()) `
            -ArrayHandling $ArrayHandling `
            -NullHandling $NullHandling `
            -Recursive:$Recursive `
            -CloneBase:$CloneBase `
            | Select-Object -Last 1

        $signal.MergeSignal(@($mergeSignal))

        if ($mergeSignal.Success()) {
            $signal.SetResult($mergeSignal.GetResult())
            $signal.LogInformation("✅ Merge completed successfully using unified memory.")
        }
        else {
            $signal.LogWarning("Merge failed in unified memory flow.")
        }
    }
    catch {
        $signal.LogCritical("🔥 Exception during unified memory merge: $($_.Exception.Message)", $null, $_)
    }

    return $signal
}