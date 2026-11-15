# PSCustomObject boundary adaptation; canonical native methods are never shadowed.
function Start-Signal { param([string]$Name,[object]$ReversePointer=$null) [SignalGraph.Signal]::Start($Name,$ReversePointer) }
function Resolve-Graph { param($Signal) [SignalGraph.Graph]::ResolveGraph($Signal) }
function New-SignalPointerFork {
    param([SignalGraph.Signal]$SourceSignal,[string]$Name,$ReversePointer=$null,[SignalGraph.Graph]$TargetGraph=$null,[string]$CollisionAction='PreserveTarget',[string[]]$ExcludeKeys=$null,[switch]$CopyJacket,[switch]$CopyResult)
    [SignalGraph.GraphUtilities]::NewSignalPointerFork($SourceSignal,$Name,$ReversePointer,$TargetGraph,[SignalGraph.ForkCollisionAction]$CollisionAction,$ExcludeKeys,[bool]$CopyJacket,[bool]$CopyResult)
}
function Resolve-PathFromDictionary {
    param([Parameter(Mandatory)]$Dictionary,[Parameter(Mandatory)][string]$Path,$Default,[string]$SignalLevel='Critical',[string[]]$SignalTags=$null)
    $op=[SignalGraph.Signal]::Start('Resolve-PathFromDictionary',$Dictionary)
    try {
        foreach($candidate in [SignalGraph.Paths]::Split($Path,',')){
            $current=$Dictionary;$found=$true
            foreach($segment in [SignalGraph.Paths]::Split($candidate,'.')){
                if($null -eq $current){$found=$false;break}
                # Native parser retains quoted/filter grammar; only PS member access is adapted.
                $key=switch -Exact ($segment){'%'{'Jacket'} '*'{'Pointer'} '@'{'Result'} '!'{'ReversePointer'} '~'{'Control'} '#'{'Grid'} '$'{'Signal'} default{$segment.Trim("'",'"')}}
                if($segment -ceq '$' -and $current -is [SignalGraph.Signal]){continue}
                if($current -is [Collections.IList] -and $segment -notmatch '^\d+$' -and $key -ne 'Count'){
                    $property='Name';$expected=$key
                    if($key.Contains('=')){$parts=$key.Split('=',2);$property=$parts[0];$expected=$parts[1].Trim("'",'"')}
                    $matches=@($current|Where-Object{[string]$_.$property -ieq $expected})
                    if(-not $matches.Count){$found=$false;break};$current=$matches[0];continue
                }
                if($segment.Contains('[')){
                    $filter=[SignalGraph.Paths]::InvokeParseFilterSegment($segment)
                    $array=$current.($filter.ArrayKey)
                    if($filter.IsFilter){
                        $current=@($array|Where-Object{
                            $item=$_;$matches=$true
                            foreach($term in $filter.Filters){
                                $value=[string]$item.($term.Key)
                                $matches=$matches -and $(switch($term.Op){
                                    '=' {$value -ieq $term.Value}
                                    '!=' {$value -ine $term.Value}
                                    '~=' {$value -clike $term.Value}
                                    '~=i' {$value -like $term.Value}
                                    default {throw 'Unsupported filter operator'}
                                })
                            }
                            $matches
                        })
                    }else{$index=[int]($segment.Substring($segment.IndexOf('[')+1).TrimEnd(']'));if($index -lt 0 -or $index -ge @($array).Count){$found=$false;break};$current=$array[$index]}
                    continue
                }
                if($current -is [Collections.IDictionary]){
                    $actual=@($current.Keys|Where-Object{[string]$_ -ieq $key}|Select-Object -First 1)
                    if(-not $actual.Count){$found=$false;break};$current=$current[$actual[0]];continue
                }
                if($current -is [Collections.IList] -and $segment -match '^\d+$'){$index=[int]$segment;if($index -ge $current.Count){$found=$false;break};$current=$current[$index];continue}
                $property=$current.PSObject.Properties[$key]
                if($null -eq $property){$found=$false;break};$current=$property.Value
            }
            if($found -and $null -ne $current){$op.Result=$current;return $op}
        }
        if($PSBoundParameters.ContainsKey('Default')){$op.Result=$Default}else{
            $hostType=if($null -eq $current){'<null>'}else{$current.GetType().FullName}
            $keys=if($current -is [Collections.IDictionary]){(@($current.Keys)|Select-Object -First 12) -join '|'}else{(@($current.PSObject.Properties.Name)|Select-Object -First 12) -join '|'}
            $null=$op.LogMessage($SignalLevel,"No supplied path resolved: $Path; segment=$segment; host=$hostType; keys=$keys",$SignalTags)
        }
    }catch{$null=$op.LogCritical($_.Exception.Message,$null,$_.Exception)}
    $op
}
function Resolve-InnerPathFromDictionary {param($Dictionary,[string]$Path,$Default,[string]$SignalLevel='Critical',[string[]]$SignalTags) Resolve-PathFromDictionary @PSBoundParameters}
function Get-ResolvedValueFromPathSignal {param($Dictionary,[string]$Path) Resolve-PathFromDictionary $Dictionary $Path}
function Invoke-ParseFilterSegment {param([string]$Segment) [SignalGraph.Paths]::InvokeParseFilterSegment($Segment)}
function Resolve-PathHydration {param([string]$CompactPath,[bool]$SignalFirst=$true) [SignalGraph.Paths]::ResolvePathHydration($CompactPath,$SignalFirst)}
function Add-PathToDictionary {
    param($Dictionary,[string]$Path,$Value,[string]$AddStyle)
    $pathSegments=[SignalGraph.Paths]::Split($Path,'.')
    if($pathSegments.Count -gt 1){
        $parentPath=($pathSegments[0..($pathSegments.Count-2)] -join '.')
        $parentSignal=Resolve-PathFromDictionary $Dictionary $parentPath -Default $null
        if($parentSignal.HasResult() -and $parentSignal.Result.GetType() -eq [System.Management.Automation.PSCustomObject]){
            return Add-PathToDictionary -Dictionary $parentSignal.Result -Path $pathSegments[$pathSegments.Count-1] -Value $Value -AddStyle $AddStyle
        }
    }
    if($Dictionary.GetType() -eq [System.Management.Automation.PSCustomObject]){
        $op=[SignalGraph.Signal]::Start('Add-PathToDictionary',$Dictionary)
        try{
            $segments=[SignalGraph.Paths]::Split($Path,'.');$parent=$Dictionary
            for($i=0;$i -lt $segments.Count-1;$i++){
                $key=$segments[$i].Trim("'",'"');$member=$parent.PSObject.Properties[$key]
                if($null -eq $member){$null=$parent|Add-Member -NotePropertyName $key -NotePropertyValue ([ordered]@{});$member=$parent.PSObject.Properties[$key]}
                $parent=$member.Value
            }
            $key=$segments[$segments.Count-1].Trim("'",'"')
            if(-not $parent.PSObject.Properties[$key] -and $parent -isnot [Collections.IDictionary]){
                $null=$parent|Add-Member -NotePropertyName $key -NotePropertyValue $Value
            }elseif($AddStyle -eq 'Append' -and $null -ne $Value -and $Value.GetType() -eq [System.Management.Automation.PSCustomObject]){
                $target=$parent.$key
                foreach($property in $Value.PSObject.Properties){if($target -is [Collections.IDictionary]){$target[$property.Name]=$property.Value}elseif($target.PSObject.Properties[$property.Name]){$target.($property.Name)=$property.Value}else{$null=$target|Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value}}
            }elseif($parent -is [Collections.IDictionary]){$parent[$key]=$Value}elseif($parent.PSObject.Properties[$key]){$parent.$key=$Value}else{$null=$parent|Add-Member -NotePropertyName $key -NotePropertyValue $Value}
            $op.Result=$Dictionary
        }catch{$null=$op.LogCritical($_.Exception.Message,$null,$_.Exception)}
        return $op
    }
    # Source callers omit Grid after a graph pointer when registering a member.
    # Native mutation requires that structural edge explicitly.
    $nativePath=$Path -replace '(\*\.)(?![#@%!~*$])','$1#.'
    if(-not $PSBoundParameters.ContainsKey('Value') -and $nativePath.EndsWith('*')){
        $existing=Resolve-PathFromDictionary $Dictionary $nativePath -Default $null
        if($existing.HasResult()){return $existing}
        $Value=[SignalGraph.Graph]::Start('AutoCreated',$Dictionary,$true).Result
    }
    # The PS API's Append flag applies only to ordinary PS object properties;
    # symbolic Result and graph registration writes retain replacement semantics.
    if($AddStyle -eq 'Append'){$AddStyle='Replace'}
    $operation=[SignalGraph.Mutations]::AddPathToDictionary($Dictionary,$nativePath,$Value,$AddStyle)
    if(($operation.Failure() -or $Dictionary.Name -eq 'MergeSignal') -and $env:ST_NATIVE_ABI_TRACE){
        $diagnostic=[ordered]@{Operation='Add';Path=$Path;NativePath=$nativePath;RootType=$Dictionary.GetType().FullName;RootName=$Dictionary.Name;RootHasResult=$Dictionary.HasResult();RootKeys=@($Dictionary.Result.Keys);ValueType=if($null -eq $Value){'<null>'}else{$Value.GetType().FullName};Entries=@($operation.Entries|ForEach-Object Message)}
        [IO.File]::AppendAllText($env:ST_NATIVE_ABI_TRACE,($diagnostic|ConvertTo-Json -Depth 5 -Compress)+[Environment]::NewLine)
    }
    $operation
}
function Remove-PathFromDictionary {param($Dictionary,[string]$Path) [SignalGraph.Mutations]::RemovePathFromDictionary($Dictionary,$Path)}
function Move-PathInDictionary {param($Dictionary,[string]$SourcePath,[string]$DestinationPath) [SignalGraph.Mutations]::MovePathInDictionary($Dictionary,$SourcePath,$DestinationPath)}
function Resolve-GraphForJsonArray {
    param([SignalGraph.Signal]$ConductionSignal,$Plan,[string]$SourcePath='%.@',[string]$GraphName,[SignalGraph.Signal]$ItemSignal)
    $op=[SignalGraph.Signal]::Start('Resolve-GraphForJsonArray',$ConductionSignal)
    $array=Resolve-PathFromDictionary $ItemSignal $SourcePath
    if($op.MergeSignalAndVerifyFailure(@($array))){return $op}
    $namePath=(Resolve-PathFromDictionary $Plan NamePath -Default Name).Result
    $graph=[SignalGraph.Graph]::Start("Graph:$GraphName",$op,$true).Result
    foreach($item in @($array.Result)){
        $id=Resolve-PathFromDictionary $item $namePath
        if($op.MergeSignalAndVerifyFailure(@($id))){return $op}
        $jacket=[SignalGraph.Signal]::Start("Node:$($id.Result):Signal",$item);$jacket.Result=$item
        $node=[SignalGraph.Signal]::Start("Node:$($id.Result)",$item);$node.Jacket=$jacket
        $null=$graph.RegisterSignal([string]$id.Result,$node)
    }
    $null=$graph.Complete();$op.Result=$graph;$op
}

function Get-STSignalCriticalSummary {
    param([SignalGraph.Signal]$Signal)
    ($Signal.Entries | Where-Object Level -eq 'Critical' | ForEach-Object Message) -join ','
}