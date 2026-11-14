
function Convert-JsonToHashtable {
    param (
        [Parameter(Mandatory)]
        [object]$parsed
    )

    #$parsed = $JsonString | ConvertFrom-Json -Depth 20

    if ($parsed -is [System.Collections.IEnumerable] -and -not ($parsed -is [string])) {
        return $parsed | ForEach-Object {
            $ht = @{}
            $_.PSObject.Properties | ForEach-Object {
                $ht[$_.Name] = $_.Value
            }
            $ht
        }
    } else {
        $ht = @{}
        $parsed.PSObject.Properties | ForEach-Object {
            $ht[$_.Name] = $_.Value
        }
        return $ht
    }
}