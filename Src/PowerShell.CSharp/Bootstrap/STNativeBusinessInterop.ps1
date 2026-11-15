function ConvertTo-STBusinessMetadata {
    param($Value)
    if($null -eq $Value){return $null}
    if($Value -is [SignalGraph.Signal] -or $Value -is [SignalGraph.Graph] -or $Value -is [type]){return $Value}
    if($Value -is [Collections.IDictionary]){
        $properties=[ordered]@{}
        foreach($key in $Value.Keys){$properties[[string]$key]=ConvertTo-STBusinessMetadata $Value[$key]}
        return [pscustomobject]$properties
    }
    if($Value -is [Collections.IList]){return ,@($Value|ForEach-Object{ConvertTo-STBusinessMetadata $_})}
    return $Value
}

function ConvertTo-STNativeMetadata {
    param($Value)
    while($Value -is [SignalGraph.Signal]){$Value=$Value.GetResult($true)}
    if($null -eq $Value){return $null}
    if($Value -is [SignalGraph.Graph] -or $Value -is [type]){return $Value}
    if($Value -is [Collections.IDictionary]){
        $map=[Collections.Specialized.OrderedDictionary]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($key in $Value.Keys){$map[$key]=ConvertTo-STNativeMetadata $Value[$key]}
        return ,$map
    }
    if($Value.GetType() -eq [Management.Automation.PSCustomObject]){
        $map=[Collections.Specialized.OrderedDictionary]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($property in $Value.PSObject.Properties){$map[$property.Name]=ConvertTo-STNativeMetadata $property.Value}
        return ,$map
    }
    if($Value -is [Collections.IList]){return ,@($Value|ForEach-Object{ConvertTo-STNativeMetadata $_})}
    return $Value
}
