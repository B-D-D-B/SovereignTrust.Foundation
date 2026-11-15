param([Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)]$Selection,[string]$Cycle)
$ErrorActionPreference='Stop'
function Test-NativePureEffectClosure($Module,$Ast) {
    $queue=[Collections.Generic.Queue[object]]::new();$queue.Enqueue($Ast)
    $seen=@{};$reasons=[Collections.Generic.List[string]]::new();$visited=[Collections.Generic.List[string]]::new()
    $pure=@('Select-Object','Where-Object','ForEach-Object','Out-Null','ConvertTo-Json','ConvertFrom-Json','Add-Member','Get-Member','Get-Date','New-Guid','Test-Path','Get-Item','Get-Command','Write-Verbose','Write-Debug','Write-Host','Measure-Object','Sort-Object','Join-Path','Split-Path')
    while($queue.Count){
        $body=$queue.Dequeue()
        if($body.Extent.Text -match '(?i)\.(Open|OpenAsync|Connect|Send|SendAsync|WriteAllText|WriteAllBytes|CreateDirectory|Invoke)\s*\('){$reasons.Add('Reflective/IO/transport member activation requires a separately bound fixture');continue}
        foreach($command in $body.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst]},$true)){
            $name=$command.GetCommandName()
            if([string]::IsNullOrWhiteSpace($name)){$reasons.Add('Dynamic command activation');continue}
            if($name -in $pure -or $seen.ContainsKey($name)){continue}
            $seen[$name]=$true
            $function=& $Module {param($name) Get-Command $name -CommandType Function -ErrorAction SilentlyContinue} $name
            if($null -eq $function){$reasons.Add("Unclosed transitive command: $name");continue}
            $visited.Add($name);$queue.Enqueue($function.ScriptBlock.Ast)
        }
    }
    [pscustomobject]@{Safe=$reasons.Count -eq 0;TransitiveFunctions=$visited.ToArray();BlockedReasons=$reasons.ToArray()}
}
$siblings=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$appPath=Join-Path $siblings 'BDDB.Infrastructure/integration/sovereign-trust/content/config/STTestApp.json'
$planPath=Join-Path $siblings 'BDDB.Infrastructure/integration/sovereign-trust/content/test/plans/st-test.json'
if((Get-FileHash $appPath).Hash -cne 'A1BAEFB0FC3A433125099A9CF7AB533256DCC314A086835C907777049A1EABB4' -or (Get-FileHash $planPath).Hash -cne '2410408E1AB36E2C7FD54F85800AF3F8F79848922EA6CD03572269C3BE04B482'){throw 'Direct input drift'}
$app=Get-Content $appPath -Raw|ConvertFrom-Json
$role=@($app.Agents|Where-Object Name -CEQ sdasttest01)[0].Roles.STIntegrationTest
$foundation=@(Get-Module SovereignTrust.Foundation|Where-Object ModuleBase -EQ $Selection.Foundation.Root)
if($foundation.Count -ne 1){throw 'Canonical Foundation module required'}
$foundation=$foundation[0]
if($Cycle){
    $spec=Get-Content (Join-Path $Cycle cases.json) -Raw|ConvertFrom-Json
    if($spec.Stage -ceq 'LocalIntegration'){return & "$PSScriptRoot/NativeAdapters.Local.ps1" -RunRoot $RunRoot -Selection $Selection -Foundation $foundation -Role $role -Profile $spec.Profile}
    if($spec.Schema -cne 'ST.NativeAdapter.Cases/1' -or $spec.Start -lt 0 -or $spec.Count -lt 1 -or $spec.Start+$spec.Count -gt $Selection.AdapterModules.Count){throw 'Invalid bounded adapter matrix selection'}
    $rows=[Collections.Generic.List[object]]::new()
    foreach($entry in @($Selection.AdapterModules|Select-Object -Skip $spec.Start -First $spec.Count)){
        $row=[ordered]@{Repository=$entry.Repository;Kind=$entry.Kind;Provider=$entry.Provider;Root=$entry.Root;Files=$entry.Files.Count;Copied=$true;Syntax='Parsed in all-owned scan';Import='Unstarted';Type='Unstarted';Registration='Unstarted';Construct='Unstarted';RepresentativeActivity='Unstarted';Pass=$null;Status='Blocked';Reason=$null}
        if($entry.EntryPoints.Count -ne 1){$row.Reason='Source tree has no unique manifest/module contract (empty or nonmanifest tree).';$rows.Add($row);continue}
        try{
            $manifest=Join-Path $entry.Root $entry.EntryPoints[0]
            $data=Import-PowerShellDataFile $manifest
            $rootModule=Join-Path $entry.Root $data.RootModule
            $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($rootModule,[ref]$tokens,[ref]$errors)
            if($errors.Count){throw ('Root parser: '+($errors.Message -join '; '))}
            $allowed=@('Join-Path','Import-STSelectedFoundation','Export-ModuleMember','Set-StrictMode','Get-ChildItem','ForEach-Object','Where-Object','Get-STFoundationSelection')
            $rootText=[IO.File]::ReadAllText($rootModule)
            $packageMatch=[regex]::Match($rootText,'(?m)^\$package = Join-Path \$PSScriptRoot ''([^'']+)''')
            if($packageMatch.Success){
                $packageRoot=[IO.Path]::GetFullPath((Join-Path $entry.Root $packageMatch.Groups[1].Value))
                if(-not $packageRoot.StartsWith($entry.Root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Package root escaped selected module'}
                $packageManifest=Get-Content (Join-Path $packageRoot Package.json) -Raw|ConvertFrom-Json
                foreach($member in $packageManifest.Files){
                    if($member.Path -match '[\\/]' -or $member.Path -in '.','..'){throw 'Unsafe package member'}
                    if((Get-FileHash (Join-Path $packageRoot $member.Path)).Hash -cne $member.Sha256){throw 'Selected local package member mismatch'}
                }
                # Only local DLL loading is permitted; no code compilation/download/activation.
                $addTypes=@($ast.EndBlock.Statements|ForEach-Object{$_.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Add-Type'},$true)})
                foreach($command in $addTypes){if($command.Extent.Text -notmatch '^Add-Type -LiteralPath \(Join-Path \$package ''[A-Za-z0-9_.-]+\.dll''\)$'){throw 'Unreviewed Add-Type activation'}}
                $allowed+=@('Get-Content','ConvertFrom-Json','Get-FileHash','Add-Type')
            }
            $unsafe=@(foreach($statement in $ast.EndBlock.Statements){
                if($statement -is [Management.Automation.Language.FunctionDefinitionAst] -or $statement -is [Management.Automation.Language.TypeDefinitionAst]){continue}
                foreach($command in $statement.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst]},$true)){
                    if($command.InvocationOperator -eq [Management.Automation.Language.TokenKind]::Dot){continue}
                    $name=$command.GetCommandName();if([string]::IsNullOrWhiteSpace($name)){'<dynamic-command>'}elseif($name -notin $allowed){$name}
                }
            })
            $row.ImportEffectInspection=[ordered]@{RootModule=$rootModule;UnreviewedTopLevelCommands=$unsafe;ProviderConstructAllowed=$false}
            if($unsafe.Count){$row.Reason='Import blocked before execution: unreviewed top-level effect closure: '+($unsafe -join ',');$rows.Add($row);continue}
            $wire=$entry.Repository+'.'+$entry.Kind+'.'+$entry.Provider
            $type=Resolve-STNativeAdapterType -Selection $Selection -WirePath $wire -FullType ($entry.Kind+'_'+$entry.Provider)
            $row.Import='Loaded';$row.Type=$type.FullName;$row.Pass=$true;$row.Status='ImportTypePassed'
            $row.Reason='Construct/activity effect closure pending; import/type only, no provider capability acceptance.'
            if($spec.Stage -eq 'SafeBoundary'){
                $module=@(Get-Module -All|Where-Object Path -EQ $rootModule)[0]
                $class=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.TypeDefinitionAst] -and $n.Name -ceq $type.Name},$true))
                if($class.Count -eq 0){
                    $classFile=Join-Path $entry.Root ($type.Name+'.ps1')
                    if(Test-Path $classFile){$classAst=[Management.Automation.Language.Parser]::ParseFile($classFile,[ref]$tokens,[ref]$errors);$class=@($classAst.FindAll({param($n)$n -is [Management.Automation.Language.TypeDefinitionAst] -and $n.Name -ceq $type.Name},$true))}
                }
                if($class.Count -ne 1){$row.Construct='Blocked';$row.RepresentativeActivity='Blocked';$row.Reason='No unique loaded-class source contract for effect inspection';$rows.Add($row);continue}
                $construct=@($class[0].Members|Where-Object Name -EQ Construct)
                $zeroConstructors=@($class[0].Members|Where-Object {$_.Name -ceq $type.Name -and $_.Parameters.Count -eq 0})
                $constructorSafe=$true
                foreach($ctor in $zeroConstructors){$check=Test-NativePureEffectClosure $module $ctor;if(-not $check.Safe){$constructorSafe=$false;$row.ConstructorEffectInspection=$check}}
                if(-not $constructorSafe){$row.Construct='Blocked';$row.RepresentativeActivity='Blocked';$row.Reason='Default constructor has unclosed effect activation';$rows.Add($row);continue}
                $instance=[Activator]::CreateInstance($type)
                if($construct.Count -eq 1){
                    $inspection=Test-NativePureEffectClosure $module $construct[0]
                    $row.ConstructEffectInspection=$inspection
                    # An immediate null guard is the actually selected branch: later
                    # configurable helpers are not activated by this negative probe.
                    $earlyNull=[regex]::Match($construct[0].Extent.Text,'(?s)try\s*\{\s*if\s*\(\s*\$null\s*-eq\s*\$dictionary\s*\)\s*\{(?<guard>.*?)\}')
                    $earlyNullSafe=$earlyNull.Success -and $earlyNull.Groups['guard'].Value -notmatch 'Invoke-|Connect-|Start-Process|\.Invoke\(|\.Open\(' -and $earlyNull.Groups['guard'].Value -match 'throw|return|LogCritical'
                    $row.NullInputEarlyValidation=$earlyNullSafe
                    if($inspection.Safe -or $earlyNullSafe){
                        $returned=$instance.Construct($null)|Select-Object -Last 1
                        if($returned -isnot [SignalGraph.Signal]){throw 'Null-configuration constructor returned a noncanonical operation'}
                        $row.Construct=[ordered]@{Status='NullInputBoundaryObserved';CanonicalSignal=$true;Failure=$returned.Failure();HasResult=$returned.HasResult();ConfiguredProviderAcceptance=$false}
                    }else{$row.Construct='Blocked: '+($inspection.BlockedReasons -join '; ')}
                }else{$row.Construct='Blocked: source has no unique Construct API'}
                $invoke=@($class[0].Members|Where-Object {$_.Name -ceq 'Invoke' -and $_.Parameters.Count -eq 5})
                $row.RepresentativeActivity='Blocked: configured context/resources or a source-proven early no-effect branch is required'
                if($type.GetMethod('ReadObjectAsJson')){
                    $local=Join-Path $RunRoot owned-local-json;$null=[IO.Directory]::CreateDirectory($local)
                    [IO.File]::WriteAllText((Join-Path $local fixture.json),'{"False":false,"Zero":0,"Items":[null,false,""]}',[Text.UTF8Encoding]::new($false))
                    $read=$instance.ReadObjectAsJson($local,'fixture.json')
                    $value=$read.GetResult()
                    if($read.Failure() -or $value.False -isnot [bool] -or $value.False -ne $false -or $value.Zero -ne 0 -or $value.Items.Count -ne 3 -or $null -ne $value.Items[0] -or $value.Items[1] -ne $false){throw 'Actual local provider JSON read lost typed values/cardinality'}
                    $row.RepresentativeActivity=[ordered]@{Status='ActualOwnedLocalJsonRead';CanonicalSignal=$true;FalseType=$value.False.GetType().FullName;ZeroType=$value.Zero.GetType().FullName;Items=3;MappedFiveArgumentSupport=$invoke.Count -eq 1;LiveExternalService=$false}
                }
                if($invoke.Count -eq 1 -and $invoke[0].Extent.Text -match 'switch\s*\(\$Activity\)'){
                    $unknown=$instance.Invoke('FixtureSlot','__NativeUnknownActivity__',$null,[pscustomobject]@{Config=[pscustomobject]@{}},$null)|Select-Object -Last 1
                    if($unknown -isnot [SignalGraph.Signal] -or -not $unknown.Failure()){throw 'Unknown activity did not return canonical Critical operation'}
                    $row.RepresentativeActivity=[ordered]@{Status='UnknownActivityNegativeBoundary';CanonicalCritical=$true;LiveProviderAcceptance=$false}
                }
                $row.Status='SafeBoundaryObserved';$row.Reason='Import/type plus stated negative constructor/activity boundaries only; live/configured external behavior remains unproved'
            }
        }catch{$row.Pass=$false;$row.Status='Failed';$row.Reason=$_.Exception.Message}
        $rows.Add($row)
        $rows.ToArray()|ConvertTo-Json -Depth 12|Set-Content (Join-Path $RunRoot matrix-partial.json) -Encoding utf8
    }
    $pass=@($rows|Where-Object {$_.Pass -eq $true}).Count;$fail=@($rows|Where-Object {$_.Pass -eq $false}).Count;$blocked=@($rows|Where-Object {$null -eq $_.Pass}).Count
    $constructorAttempts=@($rows|Where-Object {$_.Construct -is [Collections.IDictionary] -and $_.Construct.Status -eq 'NullInputBoundaryObserved'}).Count
    $report=[ordered]@{Scope=if($spec.Stage -ceq 'SafeBoundary'){'Selected module import/type and explicitly recorded null-constructor/negative or owned-local activity boundaries'}else{'Selected module import and declared-owner type checks only'};Pass=$pass;Fail=$fail;Blocked=$blocked;Total=$rows.Count;Skip=0;Rows=$rows.ToArray();ConstructorAttempts=$constructorAttempts;Constructed=($constructorAttempts -gt 0);ConfiguredProviderAcceptance=$false;CloudExecuted=$false;Selection=$spec}
    $report|ConvertTo-Json -Depth 15|Set-Content (Join-Path $RunRoot native-adapters.json) -Encoding utf8
    if($fail){throw "NATIVE_ADAPTER_MATRIX: $pass/$fail/$blocked of $($rows.Count)"}
    return $report
}
$cases=[Collections.Generic.List[object]]::new()
$profiles=(Get-Content (Join-Path $PSScriptRoot Fixtures/NativeAdapters/storage-dispatch.json) -Raw|ConvertFrom-Json).Cases
foreach($slot in 'Secrets','RemoteContent'){
    $definition=@($role.Adapters|Where-Object Name -CEQ $slot)
    if($definition.Count -ne 1){throw "Direct declaration missing: $slot"}
    $wire=$definition[0].VirtualPath
    $fullType=($wire.Split('.')[2..3]) -join '_'
    try{
        $pathSignal=& $foundation {param($wire) Resolve-ModulePathSignal -WirePath $wire|Select-Object -Last 1} $wire
        if($pathSignal.Failure()){throw 'Normal module metadata resolution failed'}
        $metadata=$pathSignal.GetResult().GetJacketResult($true)
        if([string]$metadata.RelativeFilePath -notmatch 'PowerShell\.CSharp'){throw 'Normal module path did not select development tree'}
        $type=Resolve-STNativeAdapterType -Selection $Selection -WirePath $wire -FullType $fullType
        if($type -isnot [type] -or $type.Name -cne $fullType){throw 'Normal declaration resolved wrong class'}
        Assert-STFoundationSelection $Selection -RequireLoaded
        $cases.Add([ordered]@{Id="direct.$slot.normal-module-type";Pass=$true;WirePath=$wire;Class=$type.FullName;ModuleRelativePath=$metadata.RelativeFilePath;Constructed=$false;ActivityInvoked=$false})
        $profile=@($profiles|Where-Object Slot -CEQ $slot)[0]
        $configuration=$definition[0]|ConvertTo-Json -Depth 30|ConvertFrom-Json
        $configuration.Routes[0].Address=$profile.Address
        if($slot -eq 'Secrets'){$configuration.Resource[0].Vault=$profile.Vault}
        else{$configuration.Resource[0].Container=$profile.Container}
        $instance=[Activator]::CreateInstance($type)
        $constructed=$instance.Construct($configuration)|Select-Object -Last 1
        if($constructed -isnot [SignalGraph.Signal] -or $constructed.Failure()){throw ('Controlled constructor failed: '+(($constructed.Entries|ForEach-Object Message) -join '; '))}
        $cases.Add([ordered]@{Id="fixture.$slot.construct";Pass=$true;Boundary='Inert configuration parsing only';LiveService=$false})
        $entry=Get-STNativeAdapterEntry $Selection $wire
        $data=Import-PowerShellDataFile (Join-Path $entry.Root $entry.EntryPoints[0])
        $module=@(Get-Module -All|Where-Object Path -EQ (Join-Path $entry.Root $data.RootModule))[0]
        $state=@{Requests=[Collections.Generic.List[object]]::new();Response=$profile.Response;Fail=$false}
        if($state.Response -is [pscustomobject] -and $null -ne $state.Response.PSObject.Properties['StatusCode']){$state.Response.StatusCode=[int]$state.Response.StatusCode}
        & $module {
            param($state)
            $script:NativeBoundaryState=$state
            function script:Invoke-MappedAdapter {
                param($Adapter,$Activity,$Signal,$Plan,$ItemSignal)
                if($Adapter -cne 'Condenser.Rest' -or $Activity -cne 'Get'){throw 'Fixture denied unexpected effect boundary'}
                $script:NativeBoundaryState.Requests.Add([ordered]@{Adapter=$Adapter;Activity=$Activity;Config=$Plan.Config;Signal=$Signal;ItemSignal=$ItemSignal})
                $result=[SignalGraph.Signal]::Start('Controlled REST response',$ItemSignal)
                if($script:NativeBoundaryState.Fail){return $result.LogCritical('Controlled downstream failure')}
                $result.SetResult($script:NativeBoundaryState.Response)
                return $result
            }
        } $state
        try{
            $conduction=[SignalGraph.Signal]::Start('fixture conduction');$item=[SignalGraph.Signal]::Start('fixture item')
            $plan=[pscustomobject]@{Container='';Resource=$profile.Resource;Config=[pscustomobject]@{VirtualPath=if($slot -eq 'Secrets'){$profile.Resource}else{'/'+$profile.Resource}}}
            $result=$instance.Invoke($slot,'Read',$conduction,$plan,$item)|Select-Object -Last 1
            if($result.Failure() -or $state.Requests.Count -ne 1 -or $state.Requests[0].Config.Uri -cne $profile.ExpectedUri -or $result.GetResult() -cne $profile.ExpectedResult -or -not [object]::ReferenceEquals($state.Requests[0].Signal,$conduction) -or -not [object]::ReferenceEquals($state.Requests[0].ItemSignal,$item)){throw ('Controlled Read request/result/identity failed: '+(($result.Entries|ForEach-Object Message) -join '; '))}
            $cases.Add([ordered]@{Id="fixture.$slot.real-read-dispatch";Pass=$true;Boundary='Actual provider request construction + controlled REST response';LiveService=$false;Method=$state.Requests[0].Config.Method;Uri=$state.Requests[0].Config.Uri})
            $state.Fail=$true;$result=$instance.Invoke($slot,'Read',$conduction,$plan,$item)|Select-Object -Last 1
            if(-not $result.Failure() -or $state.Requests.Count -ne 2){throw 'Controlled downstream failure was not propagated'}
            $cases.Add([ordered]@{Id="fixture.$slot.failure-propagation";Pass=$true;LiveService=$false})
            $result=$instance.Invoke($slot,'UnknownFixtureActivity',$conduction,$plan,$item)|Select-Object -Last 1
            if(-not $result.Failure() -or $state.Requests.Count -ne 2){throw 'Unknown activity reached downstream effect'}
            $cases.Add([ordered]@{Id="fixture.$slot.unknown-no-dispatch";Pass=$true;LiveService=$false})
        }finally{
            & $module {Remove-Item Function:script:Invoke-MappedAdapter -ErrorAction SilentlyContinue;Remove-Variable NativeBoundaryState -Scope Script -ErrorAction SilentlyContinue}
        }
    }catch{$cases.Add([ordered]@{Id="fixture.$slot.boundary-failure";Pass=$false;Error=$_.Exception.Message;Boundary='Controlled constructor/request-dispatch fixture, not live provider'})}
}
$pass=@($cases|Where-Object Pass).Count
$report=[ordered]@{Scope='Actual direct declarations to selected module/type plus controlled inert constructor/REST-dispatch fixtures; NOT live provider acceptance';Pass=$pass;Fail=$cases.Count-$pass;Total=$cases.Count;Skip=0;Cases=$cases.ToArray();DirectApp=$appPath;DirectPlan=$planPath;ConfiguredConstructorAttempts=2;CloudExecuted=$false;ProviderAuthenticationInvoked=$false;NativeOrigin=Get-STSelectionProvenance $Selection}
$report|ConvertTo-Json -Depth 15|Set-Content (Join-Path $RunRoot native-adapters.json) -Encoding utf8
if($report.Fail){throw "NATIVE_ADAPTER_ASSERT: $($report.Fail)/$($report.Total): $((@($cases|Where-Object {-not $_.Pass}).Error) -join '; ')"}
$report
