# Explicit hybrid provider boundary: native registry/dispatch owns the call;
# the selected PS adapter retains its business logic and canonical SG objects.
function Get-STFailureOwnershipTable {
    # Proofs only: weak actual-object keys and immutable scope/hash tuples.
    # No execution context, object graph, or mutable PS stack is stored here.
    $domain=[AppDomain]::CurrentDomain
    [Threading.Monitor]::Enter($domain)
    try {
        $table=$domain.GetData('SovereignTrust.Foundation.FailureContextOwnership/1')
        if($null -eq $table){$table=[Runtime.CompilerServices.ConditionalWeakTable[object,object]]::new();$domain.SetData('SovereignTrust.Foundation.FailureContextOwnership/1',$table)}
        if($table -isnot [Runtime.CompilerServices.ConditionalWeakTable[object,object]]){return $null}
        return ,$table
    }finally{[Threading.Monitor]::Exit($domain)}
}
function Test-STFailureOwnership($Object,$Json,[string]$ScopeId) {
    try {
        if($null -eq $Object -or $Json -isnot [string]){return $false}
        $key=$Object
        # PSCustomObject's BaseObject is a singleton; retain its distinct PS
        # container identity. Canonical/native objects use their actual base.
        if($Object -isnot [pscustomobject]){$key=$Object.PSObject.BaseObject}
        $table=Get-STFailureOwnershipTable;$proof=$null
        if($null -eq $table -or !$table.TryGetValue($key,[ref]$proof) -or $proof -isnot [Tuple[string,string]]){return $false}
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Json)))
        return $proof.Item1 -ceq $ScopeId -and $proof.Item2 -ceq $hash
    }catch{return $false}
}
function Set-STFailureOwnership($Object,[string]$Json,[string]$ScopeId) {
    $key=$Object;if($Object -isnot [pscustomobject]){$key=$Object.PSObject.BaseObject}
    $table=Get-STFailureOwnershipTable;if($null -eq $table){return}
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Json)))
    [Threading.Monitor]::Enter($key)
    try{$null=$table.Remove($key);$table.Add($key,[Tuple]::Create($ScopeId,$hash))}finally{[Threading.Monitor]::Exit($key)}
}
function Copy-STFailureNodeOwnership($Source,$Target) {
    try{$json=Get-STFailureNodeJson $Source;$copy=Get-STFailureNodeJson $Target;if($json -is [string] -and $json -ceq $copy){$v=ConvertFrom-Json $json -AsHashtable -Depth 8;if(Test-STFailureOwnership $Source $json $v.ScopeId){Set-STFailureOwnership $Target $copy $v.ScopeId}}}catch{}
}
function Get-STVerifiedFailureNodeJson($Node,[string]$ScopeId) {
    try{$json=Get-STFailureNodeJson $Node;if($json -is [string] -and (Test-STFailureOwnership $Node $json $ScopeId)){return $json}}catch{}
    return $null
}
function Copy-STFailureContextToFreshNode($Source,$Target,[string]$ScopeId) {
    try{
        $json=Get-STVerifiedFailureNodeJson $Source $ScopeId;if($null -eq $json -or $null -eq $Target){return}
        $existing=Get-STFailureNodeJson $Target
        if($null -ne $existing){return}
        if($Target -is [Collections.IDictionary]){$Target['__STFailureContextJson']=$json}elseif($Target -is [pscustomobject]){$Target|Add-Member -NotePropertyName __STFailureContextJson -NotePropertyValue $json}else{return}
        Set-STFailureOwnership $Target $json $ScopeId
    }catch{}
}
function Suspend-STFailureHydrationContext($Node,[string]$ScopeId) {
    $json=Get-STVerifiedFailureNodeJson $Node $ScopeId
    if($null -eq $json){return $null}
    if($Node -is [Collections.IDictionary]){$null=$Node.Remove('__STFailureContextJson')}elseif($Node -is [pscustomobject]){$Node.PSObject.Properties.Remove('__STFailureContextJson')}else{return $null}
    return $json
}
function Restore-STFailureHydrationContext($Node,$Json,[string]$ScopeId) {
    try{
        if($Json -isnot [string] -or !(Test-STFailureOwnership $Node $Json $ScopeId)){return}
        if($null -ne (Get-STFailureNodeJson $Node)){return}
        if($Node -is [Collections.IDictionary]){$Node['__STFailureContextJson']=$Json}elseif($Node -is [pscustomobject]){$Node|Add-Member -NotePropertyName __STFailureContextJson -NotePropertyValue $Json}else{return}
        Set-STFailureOwnership $Node $Json $ScopeId
    }catch{}
}
function Get-STFailureTransferProofs($Node) {
    $proofs=@()
    foreach($candidate in @($Node)+@(if($Node -is [pscustomobject] -and $Node.PSObject.Properties['Steps']){@($Node.Steps)|Select-Object -First 256})){
        try{$json=Get-STFailureNodeJson $candidate;if($json -is [string]){$v=ConvertFrom-Json $json -AsHashtable -Depth 8;if(Test-STFailureOwnership $candidate $json $v.ScopeId){$proofs += [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json)))}}}catch{}
    }
    return @($proofs|Sort-Object -Unique)
}
function Get-STFailureScalar($Value) {
    if ($Value -isnot [string]) { return $null }
    if ($Value -match '(?i)(["'']?(passwords?|secrets?|tokens?|authorization|credentials?|api[ _-]?key|accountkey|sharedkey|sig|client_secret|access_token|headers?|sharedaccesssignature)["'']?\s*[:=]|\b(Bearer|Basic)\s+\S+|https?://|[\x00-\x1f])') { return '[redacted]' }
    if ($Value.Length -gt 256) { return $Value.Substring(0,244)+'[truncated]' }
    return $Value
}
function Get-STFailureOptionalString($Object,[string]$Name) {
    if($Object -is [Collections.IDictionary]){if($Object.Contains($Name) -and $Object[$Name] -is [string]){return $Object[$Name]}}
    elseif($Object -is [pscustomobject]){$property=$Object.PSObject.Properties[$Name];if($null -ne $property -and $property.Value -is [string]){return $property.Value}}
    return $null
}
function Get-STFailureWorkerProofs($Context) {
    $value=$null
    if($Context -is [Collections.IDictionary]){if($Context.Contains('FailureNodeProofs')){$value=$Context['FailureNodeProofs']}}
    elseif($Context -is [pscustomobject]){$property=$Context.PSObject.Properties['FailureNodeProofs'];if($null -ne $property){$value=$property.Value}}
    return @($value|Where-Object{$_ -is [string] -and $_ -cmatch '^[A-F0-9]{64}$'}|Select-Object -First 256)
}
function Get-STFailureNodeJson($Node) {
    if ($null -eq $Node) { return $null }
    if ($Node -is [Collections.IDictionary]) { if ($Node.Contains('__STFailureContextJson')) { return $Node['__STFailureContextJson'] }; return $null }
    if ($Node -is [pscustomobject]) { $p=$Node.PSObject.Properties['__STFailureContextJson'];if($null -ne $p){return $p.Value} }
    return $null
}
function ConvertTo-STFailureFrame($InputFrame) {
    $frame=[ordered]@{}
    foreach($key in 'InvocationId','BoundaryKind','Plan','Phase','Step','ExecutionStep','Adapter','Activity','IterationName','TaskId','DiagnosticContextUnavailable') {
        $v=if($InputFrame -is [Collections.IDictionary] -and $InputFrame.Contains($key)){$InputFrame[$key]}else{$null}
        $frame[$key]=Get-STFailureScalar $v
    }
    foreach($key in 'IterationIndex','WorkerIndex') {$v=if($InputFrame -is [Collections.IDictionary] -and $InputFrame.Contains($key)){$InputFrame[$key]}else{$null};$frame[$key]=if(($v -is [int] -or $v -is [long]) -and $v -ge 0 -and $v -le [int]::MaxValue){[int]$v}else{$null}}
    $guid=[guid]::Empty
    if(-not [guid]::TryParse([string]$frame.InvocationId,[ref]$guid)){return $null}
    return $frame
}
function ConvertFrom-STFailureContextJson($Json) {
    try {
        if($Json -isnot [string] -or [Text.Encoding]::UTF8.GetByteCount($Json) -gt 16384){return $null}
        $v=ConvertFrom-Json $Json -AsHashtable -Depth 12
        if($v.Schema -cne 'ST.Foundation.FailureContext/1' -or $v.Truncated -isnot [bool] -or @($v.Breadcrumbs).Count -gt 32){return $null}
        $guid=[guid]::Empty;if(-not [guid]::TryParse([string]$v.ScopeId,[ref]$guid)){return $null}
        $origin=ConvertTo-STFailureFrame $v.Origin;if($null -eq $origin){return $null}
        $crumbs=@();foreach($f in @($v.Breadcrumbs)){$copy=ConvertTo-STFailureFrame $f;if($null -eq $copy){return $null};$crumbs+=,$copy}
        return [ordered]@{Schema='ST.Foundation.FailureContext/1';ScopeId=$v.ScopeId;Origin=$origin;Breadcrumbs=$crumbs;Truncated=$v.Truncated}
    } catch { return $null }
}
function New-STFailureFrame($Node,$ConductionSignal,[string]$BoundaryKind,[string]$Adapter,[string]$Activity) {
    $frame=[ordered]@{InvocationId=[guid]::NewGuid().ToString();BoundaryKind=$BoundaryKind;Plan=$null;Phase=$null;Step=$null;ExecutionStep=$null;Adapter=$Adapter;Activity=$Activity;IterationIndex=$null;IterationName=$null;WorkerIndex=$null;TaskId=$null;DiagnosticContextUnavailable='NoVerifiedSourceContext'}
    try {
        $json=Get-STFailureNodeJson $Node
        if($json -is [string] -and $json.Length -le 16384){$v=ConvertFrom-Json $json -AsHashtable -Depth 8;if($v.Schema -ceq 'ST.Foundation.FailureNode/1' -and $v.ScopeId -ceq $ConductionSignal.Id -and (Test-STFailureOwnership $Node $json $v.ScopeId)){foreach($k in 'Plan','Phase','Step','IterationIndex','IterationName','WorkerIndex','TaskId','DiagnosticContextUnavailable'){if($v.Context.Contains($k)){$frame[$k]=$v.Context[$k]}}}else{$frame.DiagnosticContextUnavailable='UnverifiedScopeOrSchema'}}
        if($Node -is [pscustomobject] -and $Node.PSObject.Properties['Name']){$frame.ExecutionStep=Get-STFailureScalar $Node.Name}
    }catch{$frame.DiagnosticContextUnavailable='MalformedNodeContext'}
    return ConvertTo-STFailureFrame $frame
}
function Set-STFailureNodeContext($Node,$Frame,[string]$ScopeId,[switch]$ReplaceVerified) {
    try {
        $existing=Get-STFailureNodeJson $Node
        if($null -ne $existing){if(!$ReplaceVerified){return $false};$old=ConvertFrom-Json $existing -AsHashtable -Depth 8;if($old.Schema -cne 'ST.Foundation.FailureNode/1' -or $old.ScopeId -cne $ScopeId -or !(Test-STFailureOwnership $Node $existing $ScopeId)){return $false}}
        $text=ConvertTo-Json ([ordered]@{Schema='ST.Foundation.FailureNode/1';ScopeId=$ScopeId;Context=(ConvertTo-STFailureFrame $Frame)}) -Depth 8 -Compress
        if($Node -is [Collections.IDictionary]){$Node['__STFailureContextJson']=$text}else{$Node|Add-Member -NotePropertyName __STFailureContextJson -NotePropertyValue $text -Force}
        Set-STFailureOwnership $Node $text $ScopeId
        return $true
    }catch{return $false}
}
function Add-STFailureBoundary($Signal,$Frame,[string]$ScopeId) {
    if($null -eq $Signal -or $null -eq $Frame){return}
    foreach($entry in @($Signal.Entries|Where-Object Level -CEQ 'Critical')) {
        [Threading.Monitor]::Enter($entry)
        try {
            $old=$null;if($entry.Meta -is [Collections.IDictionary] -and $entry.Meta.Contains('ST.Foundation.FailureContext/1')){$raw=$entry.Meta['ST.Foundation.FailureContext/1'];$old=ConvertFrom-STFailureContextJson $raw;if($null -eq $old -or !(Test-STFailureOwnership $entry $raw $old.ScopeId)){$null=$entry.AddProperty('ST.Foundation.FailureContext.UnverifiedScope',$ScopeId);continue}}
            if($null -eq $old){$old=[ordered]@{Schema='ST.Foundation.FailureContext/1';ScopeId=$ScopeId;Origin=(ConvertTo-STFailureFrame $Frame);Breadcrumbs=@();Truncated=$false}}
            else {
                if($old.ScopeId -cne $ScopeId){
                    $imported=if($entry.Meta.Contains('ST.Foundation.FailureContext.ImportedScope')){$entry.Meta['ST.Foundation.FailureContext.ImportedScope']}else{$null}
                    if($imported -ceq 'Pending'){$null=$entry.AddProperty('ST.Foundation.FailureContext.ImportedScope',$ScopeId)}
                    elseif($imported -cne $ScopeId){$null=$entry.AddProperty('ST.Foundation.FailureContext.UnverifiedScope',$ScopeId);continue}
                }
                if($old.Origin.InvocationId -cne $Frame.InvocationId -and @($old.Breadcrumbs|Where-Object InvocationId -CEQ $Frame.InvocationId).Count -eq 0){if(@($old.Breadcrumbs).Count -lt 32){$old.Breadcrumbs=@($old.Breadcrumbs)+@((ConvertTo-STFailureFrame $Frame))}else{$old.Truncated=$true}}
            }
            $text=ConvertTo-Json $old -Depth 10 -Compress
            foreach($checkedFrame in @($old.Origin)+@($old.Breadcrumbs)){if(@($checkedFrame.Values|Where-Object{$_ -is [string] -and $_.EndsWith('[truncated]')}).Count -gt 0){$old.Truncated=$true}}
            $text=ConvertTo-Json $old -Depth 10 -Compress
            if([Text.Encoding]::UTF8.GetByteCount($text) -gt 16384){$old.Breadcrumbs=@();$old.Truncated=$true;$text=ConvertTo-Json $old -Depth 10 -Compress}
            $null=$entry.AddProperty('ST.Foundation.FailureContext/1',$text)
            Set-STFailureOwnership $entry $text $old.ScopeId
        } catch { } finally {[Threading.Monitor]::Exit($entry)}
    }
}
function Get-STEntryFailureContextJson($Entry) {
    [Threading.Monitor]::Enter($Entry)
    try {if($Entry.Meta -is [Collections.IDictionary] -and !$Entry.Meta.Contains('ST.Foundation.FailureContext.UnverifiedScope') -and $Entry.Meta.Contains('ST.Foundation.FailureContext/1')){$raw=$Entry.Meta['ST.Foundation.FailureContext/1'];$v=ConvertFrom-STFailureContextJson $raw;if($null -ne $v -and (Test-STFailureOwnership $Entry $raw $v.ScopeId)){return ConvertTo-Json $v -Depth 10 -Compress}}}catch{}finally{[Threading.Monitor]::Exit($Entry)}
    return $null
}
function Restore-STEntryFailureContext($Entry,$Json) {
    $value=ConvertFrom-STFailureContextJson $Json;if($null -ne $value){$text=ConvertTo-Json $value -Depth 10 -Compress;$null=$Entry.AddProperty('ST.Foundation.FailureContext/1',$text);Set-STFailureOwnership $Entry $text $value.ScopeId;$null=$Entry.AddProperty('ST.Foundation.FailureContext.ImportedScope','Pending')}
}
function Set-STFailureSelectedSteps($Steps,$SourceSteps,[string]$Path,$ItemSignal,$ConductionSignal,$Caller) {
    $base=New-STFailureFrame $Caller $ConductionSignal 'SelectedPhase' 'Condenser.Plan' 'InvokePhase'
    $base.Plan=$null;$base.Phase=$null;$base.Step=$null;$base.DiagnosticContextUnavailable='AmbiguousSourceSelection'
    try {
        $parts=@([SignalGraph.Paths]::Split($Path,'.'));$indices=@(0..($parts.Count-1)|Where-Object{$parts[$_] -ceq 'Phases'})
        if($indices.Count -eq 1 -and $indices[0] -eq $parts.Count-3 -and $parts[-1] -ceq 'Steps' -and @($Steps).Count -eq @($SourceSteps).Count){
            $at=$indices[0];$rootPath=$parts[0..($at-1)] -join '.';$phasePath=$parts[0..($parts.Count-2)] -join '.'
            $r=Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $rootPath -Default $null|Select-Object -Last 1;$p=Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $phasePath -Default $null|Select-Object -Last 1
            $root=$r.GetResult();$phase=$p.GetResult()
            if($null -ne $root -and $null -ne $phase -and [object]::ReferenceEquals($phase.Steps,$SourceSteps)){$base.Plan=Get-STFailureScalar $root.Name;$base.Phase=Get-STFailureScalar $phase.Name;$base.DiagnosticContextUnavailable=$null}
        }
        for($i=0;$i -lt @($Steps).Count;$i++){$f=[ordered]@{};foreach($k in $base.Keys){$f[$k]=$base[$k]};$f.InvocationId=[guid]::NewGuid().ToString();if($null -eq $base.DiagnosticContextUnavailable -and $SourceSteps[$i].Name -ceq $Steps[$i].Name){$f.Step=Get-STFailureScalar $SourceSteps[$i].Name;Copy-STFailureNodeOwnership $SourceSteps[$i] $Steps[$i]}else{$f.DiagnosticContextUnavailable='SourceStepPairingUnavailable'};$null=Set-STFailureNodeContext $Steps[$i] $f $ConductionSignal.Id -ReplaceVerified}
    }catch{$base.DiagnosticContextUnavailable='SourceSelectionUnavailable'}
    return $base
}
function Copy-STFailurePhaseContext($SourceSignal,$Phase,$ConductionSignal) {
    try {if($SourceSignal.Meta.Contains('__STFailureContextJson')){$text=$SourceSignal.Meta['__STFailureContextJson'];if(Test-STFailureOwnership $SourceSignal $text $ConductionSignal.Id){$v=ConvertFrom-Json $text -AsHashtable -Depth 8;$null=Set-STFailureNodeContext $Phase $v.Context $ConductionSignal.Id}}}catch{}
}
function Set-STFailureWorkerContext($Node,[string]$ExpectedScope,$Runtime,[int]$Index,[string]$TaskId,[string[]]$Proofs=@()) {
    try {
        $json=Get-STFailureNodeJson $Node;if($json -isnot [string]){return};$v=ConvertFrom-Json $json -AsHashtable -Depth 8
        if($v.Schema -cne 'ST.Foundation.FailureNode/1' -or $v.ScopeId -cne $ExpectedScope){return}
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json)));if($hash -notin $Proofs){return}
        $v.ScopeId=$Runtime.ConductionSignal.Id;$v.Context.WorkerIndex=$Index;$v.Context.TaskId=Get-STFailureScalar $TaskId
        if($Node -is [Collections.IDictionary]){$Node['__STFailureContextJson']=ConvertTo-Json $v -Depth 8 -Compress}else{$Node.__STFailureContextJson=ConvertTo-Json $v -Depth 8 -Compress}
        Set-STFailureOwnership $Node (Get-STFailureNodeJson $Node) $v.ScopeId
        if($Node.PSObject.Properties['Steps']){foreach($step in @($Node.Steps)){Set-STFailureWorkerContext $step $ExpectedScope $Runtime $Index $TaskId $Proofs}}
    }catch{}
}
function Invoke-STNativeMappedAdapter {
    param($MappedAdapter,[string]$Family,[string]$Slot,[string]$Activity,[SignalGraph.Signal]$ConductionSignal,$Plan,[SignalGraph.Signal]$ItemSignal)
    $owner=$MappedAdapter.Signal.GetJacket()
    $native=$owner.NativeRuntime
    if($null -eq $native){throw 'ST_NATIVE_RUNTIME: selected mapped adapter has no native conductor'}
    $failureFrame=New-STFailureFrame $Plan $ConductionSignal 'Adapter' ($Family+'.'+$Slot) $Activity
    if($native.NativeFamiliesInitialized){$result=[SovereignTrust.Foundation.Wrappers.Adapters.AdapterDispatcher]::Invoke($native,$Family,$Slot,$Activity,$ConductionSignal,$Plan,$ItemSignal,$Family);Add-STFailureBoundary $result $failureFrame $ConductionSignal.Id;return $result}
    $callbackScript={
        param($slot,$activity,$conduction,$plan,$item)
        $MappedAdapter.Invoke($slot,$activity,$conduction,$plan,$item)|Select-Object -Last 1
    }.GetNewClosure()
    $callback=[System.Func[string,string,SignalGraph.Signal,object,SignalGraph.Signal,SignalGraph.Signal]]$callbackScript
    $bound=[SovereignTrust.Foundation.Wrappers.Adapters.AdapterDispatcher]::Bind($native,$Family,$MappedAdapter,$callback)
    if($bound.Failure()){return $bound}
    $result=[SovereignTrust.Foundation.Wrappers.Adapters.AdapterDispatcher]::Invoke($native,$Family,$Slot,$Activity,$ConductionSignal,$Plan,$ItemSignal,$Family)
    Add-STFailureBoundary $result $failureFrame $ConductionSignal.Id
    $result
}
