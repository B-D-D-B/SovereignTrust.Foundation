#TODO Review if this can be done in Resolve-PathFromDictionaryNoSignal
#TODO This could be done like a single path and if it has a node that has a =, like .name=xyz. then it knows to check and array instead of dictionary path
function Get-VirtualValueFromJson {
    param (
        [Parameter(Mandatory)]
        [psobject]$JsonObject,

        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory)]
        [string]$VirtualPath
    )

    # Get the initial array from the root path
    $rootObject = $JsonObject
    foreach ($part in $RootPath -split '\.') {
        $rootObject = $rootObject.$part
        if (-not $rootObject) {
            throw "Invalid root path: $RootPath"
        }
    }

    # Parse the virtual path
    $segments = $VirtualPath -split '\.'
    if ($segments.Count -ne 2) {
        throw "VirtualPath must be in format <name>.<property>, e.g. 'direction.value'"
    }

    $matchName = $segments[0]
    $matchProperty = $segments[1]

    # Find the object in the array where name matches
    $match = $rootObject | Where-Object { $_.name -eq $matchName }
    if (-not $match) {
        throw "No item found with name '$matchName' in $RootPath"
    }

    return $match.$matchProperty
}
