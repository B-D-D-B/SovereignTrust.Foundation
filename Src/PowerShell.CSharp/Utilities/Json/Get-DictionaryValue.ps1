
function Get-DictionaryValue {
    param (
        [Parameter(Mandatory)]
        $Dictionary,

        [Parameter(Mandatory)]
        [string]$Key
    )

    if ($Dictionary -is [System.Collections.IDictionary] -and $Dictionary.Contains($Key)) {
        return $Dictionary[$Key]
    }
    elseif ($Dictionary -is [pscustomobject] -and $Dictionary.PSObject.Properties.Match($Key)) {
        return $Dictionary.$Key
    }

    return $null
}