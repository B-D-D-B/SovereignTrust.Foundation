param($RunRoot,$Selection,$Foundation,$Role,[string]$Profile='Core')
$ErrorActionPreference='Stop'
$cases=[Collections.Generic.List[object]]::new()
if(-not $Profile){$Profile='Core'}
$registrationRows=@()
function Check($Id,[scriptblock]$Body){try{& $Body;$cases.Add(@{Id=$Id;Pass=$true})}catch{$cases.Add(@{Id=$Id;Pass=$false;Error=$_.Exception.Message})}finally{$cases.ToArray()|ConvertTo-Json -Depth 12|Set-Content (Join-Path $RunRoot local-partial.json) -Encoding utf8}}
if($Profile -ceq 'Core'){
Check 'axiom.actual-parse-no-media' {
    $entry=@($Selection.AdapterModules|Where-Object { $_.Repository -ceq 'SDAFusion.Adapters' -and $_.Kind -ceq 'Condenser' -and $_.Provider -ceq 'AxiomArtists'})[0]
    $type=Resolve-STNativeAdapterType $Selection 'SDAFusion.Adapters.Condenser.AxiomArtists.Fixture' 'Condenser_AxiomArtists'
    $instance=[Activator]::CreateInstance($type)
    $jacket=[pscustomobject]@{Config=[pscustomobject]@{Roots=[pscustomobject]@{Media=(Join-Path $RunRoot media);Staging=(Join-Path $RunRoot staging)}}}
    $op=$instance.Construct($jacket)
    if($op.Failure()){throw 'Axiom inert root configuration rejected'}
    $work=[pscustomobject]@{State=[pscustomobject]@{TextStatus='Initial'};RawText=$null;Parsed=$null;NeedText=$true}
    $config=[pscustomobject]@{Work=$work;Response=[pscustomobject]@{choices=@([pscustomobject]@{message=[pscustomobject]@{content='{"Item":"fixture","Prompt":"prompt"}'}})}}
    $parent=[SignalGraph.Signal]::Start('local Axiom item')
    $result=$instance.Invoke('Fixture','ParseCreationResponse',[SignalGraph.Signal]::Start('local conduction'),[pscustomobject]@{Config=$config},$parent)
    $value=$result.GetResult()
    if($result.Failure() -or $value.Parsed.Item -cne 'fixture' -or $value.Parsed.Prompt -cne 'prompt' -or $value.State.TextStatus -cne 'ResponseStored' -or $value.NeedText -or $work.State.TextStatus -cne 'Initial' -or -not [object]::ReferenceEquals($result.ReversePointer,$parent)){throw 'Axiom parse result/input isolation/native parent mismatch'}
    if((Test-Path $jacket.Config.Roots.Media) -or (Test-Path $jacket.Config.Roots.Staging)){throw 'Parse activity unexpectedly created media/staging outputs'}
}
Check 'native-fab.direct-json-lazy-type-resolution' {
    $definitions=@($Role.Adapters|Where-Object Name -In 'Secrets','RemoteContent')
    if($definitions.Count -ne 2){throw 'Exact direct app declarations missing'}
    $observed=& $Foundation {
        param($definitions,$root)
        $envDefinition=[pscustomobject]@{Name='NativeFabOffline';Config=[pscustomobject]@{ContentRootPath=$root;SupportParallelism=$false};Steps=@()}
        $init=Initialize-STEnvironment $envDefinition|Select-Object -Last 1
        if($init.Failure()){throw ('Native empty-runtime initialization failed: '+(($init.Entries|ForEach-Object Message)-join ';'))}
        $runtime=$init.GetResult();$rows=@()
        foreach($definition in $definitions){
            $metadata=ConvertTo-STNativeMetadata $definition
            $registered=$runtime.Conductor.Fab.Register($metadata,$runtime.ConductionSignal,$true,$false)
            if($registered.Failure()){throw 'Actual direct declaration lazy registration failed'}
            $expected=($definition.VirtualPath.Split('.')[2..3])-join '_'
            $resolved=$runtime.Conductor.TypeResolver.Invoke($expected)
            $registration=$runtime.Conductor.GetRegistration('Storage.'+$definition.VirtualPath.Split('.')[4])
            if($resolved.Name -cne $expected -or [string]$registration.State -cne 'Registered' -or $null -ne $registration.Instance){throw "Lazy type provenance/state mismatch: $expected/$($registration.State)"}
            $rows+=@{Class=$resolved.FullName;State=[string]$registration.State;Constructed=$false}
        }
        $rows
    } $definitions $RunRoot
    if(@($observed).Count -ne 2){throw 'Native Fab did not resolve both direct declarations'}
}
foreach($wrong in @(@('System.Object','SovereignTrust.Adapters.Storage.AzureKeyVault.Secrets'),@('Storage_AzureStorageAccount','SovereignTrust.Adapters.Storage.AzureKeyVault.Secrets'))){
    Check ('selected-owner.reject.'+$wrong[0]) {
        $rejected=$false
        try{$null=Resolve-STNativeAdapterType $Selection $wrong[1] $wrong[0]}catch{if($_.Exception.Message -notlike 'ST_NATIVE_ADAPTER: class does not match*'){throw};$rejected=$true}
        if(-not $rejected){throw 'Framework/foreign module class was accepted'}
    }
}
Check 'selected-owner.reject-ambiguous-module' {
    $ambiguous=$Selection|ConvertTo-Json -Depth 50|ConvertFrom-Json -Depth 50
    $duplicate=@($ambiguous.AdapterModules|Where-Object {$_.Kind -ceq 'Storage' -and $_.Provider -ceq 'AzureKeyVault'})[0]
    $ambiguous.AdapterModules+=@($duplicate)
    try{$null=Resolve-STNativeAdapterType $ambiguous 'SovereignTrust.Adapters.Storage.AzureKeyVault.Secrets' 'Storage_AzureKeyVault';throw 'Ambiguous module accepted'}catch{if($_.Exception.Message -notlike 'ST_NATIVE_ADAPTER: no unique selected module*'){throw}}
}
$registrationRows=& $Foundation {
    param($role,$selection,$root)
    $init=Initialize-STEnvironment ([pscustomobject]@{Name='AllDirectLazy';Config=[pscustomobject]@{ContentRootPath=$root;SupportParallelism=$false};Steps=@()})|Select-Object -Last 1
    if($init.Failure()){throw 'Registration-stage runtime initialization failed'}
    $runtime=$init.GetResult()
    foreach($entry in $selection.AdapterModules){
        $prefix=$entry.Repository+'.'+$entry.Kind+'.'+$entry.Provider+'.'
        $definitions=@($role.Adapters|Where-Object {$_.VirtualPath.StartsWith($prefix,[StringComparison]::Ordinal)})
        if($entry.EntryPoints.Count -ne 1){@{Root=$entry.Root;Stage='Registration';Status='Blocked';Reason='Source tree has no manifest/class contract';Attempts=0};continue}
        if($definitions.Count -eq 0){@{Root=$entry.Root;Stage='Registration';Status='Blocked';Reason='No declaration for this module in the mandatory direct STTestApp host role; no alternate app/PS1 provider registrations invented';Attempts=0};continue}
        foreach($definition in $definitions){
            $registered=$runtime.Conductor.Fab.Register((ConvertTo-STNativeMetadata $definition),$runtime.ConductionSignal,$true,$false)
            if($registered.Failure()){throw ('Direct declaration registration failed: '+$definition.Name)}
            $type=$runtime.Conductor.TypeResolver.Invoke(($entry.Kind+'_'+$entry.Provider))
            @{Root=$entry.Root;Stage='Registration';Status='LazyRegisteredAndOwnedTypeResolved';Declaration=$definition.Name;Type=$type.FullName;Attempts=1;Constructed=$false;Authority='Direct STTestApp.json'}
        }
    }
} $Role $Selection $RunRoot
}
foreach($slot in @('Secrets','RemoteContent'|Where-Object {($Profile -ceq 'ConfiguredKV' -and $_ -ceq 'Secrets') -or ($Profile -ceq 'ConfiguredAS' -and $_ -ceq 'RemoteContent')})){
    foreach($lazy in $true,$false){
        Check ("controlled-fab.$slot.lazy-$lazy") {
            $profile=@((Get-Content (Join-Path $PSScriptRoot Fixtures/NativeAdapters/storage-dispatch.json) -Raw|ConvertFrom-Json).Cases|Where-Object Slot -CEQ $slot)[0]
            $definition=@($Role.Adapters|Where-Object Name -CEQ $slot)[0]|ConvertTo-Json -Depth 30|ConvertFrom-Json
            $definition.Routes[0].Address=$profile.Address
            if($slot -ceq 'Secrets'){$definition.Resource[0].Vault=$profile.Vault}else{$definition.Resource[0].Container=$profile.Container}
            & $Foundation {
                param($definition,$lazy,$root)
                $init=Initialize-STEnvironment ([pscustomobject]@{Name='ControlledFab';Config=[pscustomobject]@{ContentRootPath=$root;SupportParallelism=$false};Steps=@()})|Select-Object -Last 1
                if($init.Failure()){throw 'Controlled Fab initialization failed'}
                $runtime=$init.GetResult();$path=$definition.VirtualPath.Split('.');$key=$path[2]+'.'+$path[4]
                $registered=$runtime.Conductor.Fab.Register((ConvertTo-STNativeMetadata $definition),$runtime.ConductionSignal,$lazy,$false)
                if($registered.Failure()){throw ('Configured '+$lazy+' registration failed: '+(($registered.Entries|ForEach-Object Message)-join ';'))}
                if($lazy){$resolved=$runtime.Conductor.Resolve($key);if($resolved.Failure()){throw 'Lazy configured resolution failed'}}
                $registration=$runtime.Conductor.GetRegistration($key);$instance=$registration.Instance
                if([string]$registration.State -cne 'Resolved' -or $null -eq $instance -or $registration.Attempts -ne 1){throw 'Configured instance/state/attempt count mismatch'}
                $again=$runtime.Conductor.Resolve($key)
                if(-not [object]::ReferenceEquals($instance,$again.GetResult()) -or $registration.Attempts -ne 1){throw 'Configured cache identity mismatch'}
                $source=$runtime.Conductor.GetFamily($path[2]).Graph.Grid[$path[4]].GetProperty('FabSourceIdentity')
                $duplicate=$runtime.Conductor.Fab.Register((ConvertTo-STNativeMetadata $definition),$runtime.ConductionSignal,$false,$false)
                if(-not $duplicate.Failure() -or -not [object]::ReferenceEquals($source,$runtime.Conductor.GetFamily($path[2]).Graph.Grid[$path[4]].GetProperty('FabSourceIdentity')) -or -not [object]::ReferenceEquals($instance,$registration.Instance)){throw 'Duplicate changed source/cache ownership'}
                if(-not $lazy){
                    $bad=$definition|ConvertTo-Json -Depth 30|ConvertFrom-Json
                    $parts=$bad.VirtualPath.Split('.');$parts[4]+='Failure';$bad.VirtualPath=$parts -join '.'
                    $bad.PSObject.Properties.Remove('Slot');$bad.Routes=@();$bad.Resource=@()
                    $failed=$runtime.Conductor.Fab.Register((ConvertTo-STNativeMetadata $bad),$runtime.ConductionSignal,$false,$false)
                    $failedKey=$parts[2]+'.'+$parts[4];$failedRegistration=$runtime.Conductor.GetRegistration($failedKey)
                    $failedSource=$runtime.Conductor.GetFamily($parts[2]).Graph.Grid[$parts[4]].GetProperty('FabSourceIdentity')
                    if(-not $failed.Failure() -or [string]$failedRegistration.State -cne 'Failed' -or $failedRegistration.Attempts -ne 1 -or $null -ne $failedRegistration.Instance -or $failedSource.VirtualPath -cne $bad.VirtualPath){throw 'Invalid configured eager registration lost source/failure state'}
                    $failureAgain=$runtime.Conductor.Resolve($failedKey)
                    if(-not [object]::ReferenceEquals($failureAgain,$failedRegistration.Failure) -or $failedRegistration.Attempts -ne 1){throw 'Failed registration did not preserve cached failure'}
                }
            } $definition $lazy $RunRoot
        }
    }
}
$report=[ordered]@{Scope='Selected-owner/normal direct JSON lazy registration and controlled configured eager/lazy construction; no cloud/media activities';Pass=@($cases|Where-Object Pass).Count;Fail=@($cases|Where-Object {-not $_.Pass}).Count;Total=$cases.Count;Skip=0;Cases=$cases;RegistrationRows=@($registrationRows);CloudExecuted=$false}
$report|ConvertTo-Json -Depth 12|Set-Content (Join-Path $RunRoot native-adapters.json) -Encoding utf8
if($report.Fail){throw (($cases|Where-Object {-not $_.Pass}|ForEach-Object Error)-join '; ')}
$report
