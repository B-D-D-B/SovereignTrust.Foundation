param([Parameter(Mandatory)][string]$BinaryRoot,[Parameter(Mandatory)][string]$Receipt,
      [Parameter(Mandatory)][string]$HostNewtonsoftSha256,[Parameter(Mandatory)][string]$Inputs,
      [Parameter(Mandatory)][string]$Catalog,[Parameter(Mandatory)][string]$SuiteReceipt)
$ErrorActionPreference='Stop'
$callingCases=[Collections.Generic.List[object]]::new()
function Assert-NativeCalling([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Check-NativeCalling([string]$Id,[scriptblock]$Body){
    try{$null=& $Body;$callingCases.Add([ordered]@{Id=$Id;Pass=$true})}
    catch{$callingCases.Add([ordered]@{Id=$Id;Pass=$false;Error=$_.Exception.Message})}
    $callingCases.ToArray()|ConvertTo-Json -Depth 8|Set-Content ($Receipt+'.calling.json') -Encoding utf8
}
try {
    if($PSVersionTable.PSVersion.Major -ne 7 -or $PSVersionTable.PSVersion.Minor -ne 6){throw 'ST_NATIVE_HOST: PS7.6 required'}
    if(-not [IO.Path]::IsPathFullyQualified($Receipt) -or (Test-Path $Receipt)){throw 'ST_NATIVE_RECEIPT: new absolute path required'}
    if(@(Get-Module SignalGraph,SovereignTrust.Foundation).Count){throw 'ST_NATIVE_HOST: PS product context contaminated'}
    $names=@('Newtonsoft.Json','Microsoft.Extensions.Logging.Abstractions','SignalGraph','SovereignTrust.Foundation')
    $loaded=@{}
    foreach($name in $names){
        if($name -eq 'Newtonsoft.Json'){
            $path=(Get-Item -LiteralPath (Join-Path $PSHOME 'Newtonsoft.Json.dll')).FullName
            if((Get-FileHash $path).Hash -cne $HostNewtonsoftSha256){throw 'ST_NATIVE_HOST_JSON_HASH'}
            $existing=@([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object{$_.GetName().Name -eq $name})
            if($existing.Count -ne 1){throw 'ST_NATIVE_HOST_JSON_COUNT'}
            $asm=$existing[0]
        }else{
            $path=(Get-Item -LiteralPath (Join-Path $BinaryRoot "$name.dll")).FullName
            $asm=[Reflection.Assembly]::LoadFrom($path)
        }
        if($asm.Location -cne $path){throw "ST_NATIVE_LOCATION: $name loaded $($asm.Location)"}
        $loaded[$name]=$asm
    }
    $sg=$loaded.SignalGraph;$type=$sg.GetType('SignalGraph.Signal',$true)
    if($loaded['SovereignTrust.Foundation'].GetType('SignalGraph.Signal',$true) -ne $type){throw 'ST_NATIVE_FORWARDER: canonical type differs'}
    if($loaded['Newtonsoft.Json'].GetName().Version.ToString() -ne '13.0.0.0' -or $loaded['Microsoft.Extensions.Logging.Abstractions'].GetName().Version.ToString() -ne '9.0.0.0'){throw 'ST_NATIVE_DEPENDENCY_VERSION'}
    if(@([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object{$null -ne $_.GetType('Signal',$false)}).Count){throw 'ST_NATIVE_PS_SIGNAL: duplicate PS class definition'}
    $s=[SignalGraph.Signal]::Start('native-host',$null)
    $g=[SignalGraph.Graph]::Start('native-host',$null,$false).Result
    $s.Pointer=$g;$s.Jacket=$s;$s.Control=$s;$s.Result=@{Value=$false}
    $null=$g.RegisterSignal('Member',$s)
    $g.Grid['member'].Result.Value=$true
    if(-not [object]::ReferenceEquals($g.Grid['MEMBER'],$s) -or -not [object]::ReferenceEquals($s.Pointer,$g) -or -not [object]::ReferenceEquals($s.Jacket,$s) -or -not [object]::ReferenceEquals($s.Control,$s) -or $s.Result.Value -ne $true){throw 'ST_NATIVE_LIVE_IDENTITY'}
    $serialized=$g.ToJson($false);$op=[SignalGraph.Graph]::FromJson($serialized,$false)
    if($op.Failure() -or -not [object]::ReferenceEquals($op.Result.Grid['Member'].Pointer,$op.Result)){throw 'ST_NATIVE_GRAPH_ROUNDTRIP'}
    $contract=$loaded['Microsoft.Extensions.Logging.Abstractions'].GetType('Microsoft.Extensions.Logging.ILogger',$true)
    if(-not $contract.IsAssignableFrom($type)){throw 'ST_NATIVE_LOGGER_TYPE_IDENTITY'}
    Check-NativeCalling 'ps.start.presence.reverse' {
        $parent=[SignalGraph.Signal]::Start('parent');$value=[SignalGraph.Signal]::Start('literal',$parent)
        Assert-NativeCalling ($value.Name -ceq 'literal' -and -not $value.HasResult() -and [object]::ReferenceEquals($value.ReversePointer,$parent)) 'Start arity/name/absence/reverse differs'
    }
    Check-NativeCalling 'ps.log.omitted.null.empty.tags' {
        $value=[SignalGraph.Signal]::Start('logs')
        foreach($returned in @($value.LogInformation('omitted'),$value.LogInformation('null',$null),$value.LogInformation('empty',[string[]]@()),$value.LogWarning('warning',[string[]]@('Audit')))){
            Assert-NativeCalling ([object]::ReferenceEquals($returned,$value)) 'Logger did not return same Signal'
        }
        Assert-NativeCalling ($value.Entries.Count -eq 4 -and $value.Entries[0].Tags.Count -eq 0 -and $value.Entries[3].Tags.Contains('Audit')) 'Tags/arity/entry count differs'
    }
    Check-NativeCalling 'ps.critical.ErrorRecord.Exception' {
        $value=[SignalGraph.Signal]::Start('exception');try{throw 'captured exception'}catch{$record=$_}
        $returned=$value.LogCritical('failed',$null,$record.Exception)
        Assert-NativeCalling ([object]::ReferenceEquals($returned,$value) -and $value.Failure() -and $value.Entries[0].Exception.Message -like '*captured exception*') 'Critical third Exception binding differs'
    }
    Check-NativeCalling 'ps.LogMessage.arities' {
        $value=[SignalGraph.Signal]::Start('message');$error=[InvalidOperationException]::new('message exception')
        foreach($returned in @($value.LogMessage('Information','two'),$value.LogMessage('Warning','three',[string[]]@('Audit')),$value.LogMessage('Critical','four',[string[]]@(),$error))){Assert-NativeCalling ([object]::ReferenceEquals($returned,$value)) 'LogMessage returned another object'}
        Assert-NativeCalling ($value.Entries.Count -eq 3 -and $value.Failure() -and $value.Entries[2].Exception.Message -ceq 'message exception') 'LogMessage fourth Exception differs'
    }
    Check-NativeCalling 'ps.verbose.retry.recovery.mute' {
        $value=[SignalGraph.Signal]::Start('levels');$null=$value.LogVerbose('verbose');$null=$value.LogRetry('retry')
        Assert-NativeCalling ($value.Level -ceq 'Information' -and $value.Entries[0].Tags.Contains('Verbose') -and $value.Entries[1].Tags.Contains('Retry')) 'Verbose/Retry severity changed'
        $null=$value.LogCritical('critical');$returned=$value.LogRecovery('recover');Assert-NativeCalling ([object]::ReferenceEquals($returned,$value) -and $value.Level -ceq 'Warning' -and $value.Success()) 'Recovery did not lower current level'
        $null=$value.LogCritical('critical again');$null=$value.LogMute('mute');Assert-NativeCalling ($value.Level -ceq 'Warning' -and -not $value.Failure()) 'Mute recomputed history'
    }
    Check-NativeCalling 'ps.explicit.result.typed.presence' {
        $value=[SignalGraph.Signal]::Start('presence');$value.SetResult($false);Assert-NativeCalling ($value.HasResult() -and $value.GetResult() -ceq $false) 'Explicit false missing'
        $value.SetResult($null);Assert-NativeCalling (-not $value.HasResult()) 'Null became present'
        $absent=[SignalGraph.Signal[int]]::new();$zero=[SignalGraph.Signal[int]]::new(0)
        Assert-NativeCalling (-not $absent.HasResult() -and $absent.Result -eq 0 -and $zero.HasResult() -and $zero.Result -eq 0) 'Typed constructor binding/presence differs'
    }
    Check-NativeCalling 'ps.entry.canonical.constructor' {
        $owner=[SignalGraph.Signal]::Start('owner');$error=[InvalidOperationException]::new('entry exception')
        $entry=[SignalGraph.SignalEntry]::new($owner,'warning','entry',[string[]]@(),$error,$null)
        Assert-NativeCalling ([object]::ReferenceEquals($entry.Signal,$owner) -and $entry.Level -ceq 'Warning' -and $entry.Exception.Message -ceq 'entry exception') 'SignalEntry CLR arity/owner/level differs'
    }
    Check-NativeCalling 'ps.no.obsolete.facade.invalid.level' {
        $data=Get-TypeData SignalGraph.Signal
        Assert-NativeCalling ($null -eq $data -or @($data.Members.Keys|Where-Object {$_ -like 'PSLog*'}).Count -eq 0) 'Obsolete PSLog type data remains'
        $value=[SignalGraph.Signal]::Start('invalid');$rejected=$false;try{$null=$value.LogMessage('VerboseInformation','invalid')}catch{$rejected=$true}
        Assert-NativeCalling ($rejected -and $value.Level -ceq 'Information' -and $value.Entries.Count -eq 0) 'Invalid level accepted/mutated'
    }
    if(@($callingCases|Where-Object {-not $_.Pass}).Count){throw 'ST_NATIVE_CALLING_ASSERT: see calling receipt'}
    $suite=[Reflection.Assembly]::LoadFrom((Join-Path $BinaryRoot 'SovereignTrust.Foundation.ParityTests.dll'))
    $arguments=[object[]]::new(1);$arguments[0]=[string[]]@('--wave','1','--receipt',$SuiteReceipt,'--inputs',$Inputs,'--catalog',$Catalog)
    $suiteExit=$suite.EntryPoint.Invoke($null,$arguments)
    if($suiteExit -ne 0){throw "ST_NATIVE_HOST_SUITE: exit$suiteExit"}
    $inner=Get-Content -LiteralPath $SuiteReceipt -Raw|ConvertFrom-Json
    if(-not $inner.Pass -or $inner.Total -ne 45 -or $inner.FailCount -ne 0){throw 'ST_NATIVE_HOST_SUITE_INVENTORY'}
    $jsonBinding=@($inner.Assemblies|Where-Object{$_.FullName.StartsWith('Newtonsoft.Json,')})
    if($jsonBinding.Count -ne 1 -or $jsonBinding[0].File.Path -cne $loaded['Newtonsoft.Json'].Location -or [Newtonsoft.Json.Linq.JObject].Assembly -ne $loaded['Newtonsoft.Json'] -or [Newtonsoft.Json.JsonException].Assembly -ne $loaded['Newtonsoft.Json'] -or @([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object{$_.GetName().Name -eq 'Newtonsoft.Json'}).Count -ne 1){throw 'ST_NATIVE_JSON_TYPE_IDENTITY'}
    $result=[ordered]@{Pass=$true;Scope='PS7.6 native-only explicit assembly/type/live graph load and complete native case vector; no hybrid substitution';PowerShell=$PSVersionTable.PSVersion.ToString();Runtime=[Environment]::Version.ToString();Architecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString();Assemblies=@($names|ForEach-Object{$a=$loaded[$_];[ordered]@{Name=$a.FullName;Path=$a.Location;Sha256=(Get-FileHash $a.Location).Hash;ProductVersion=[Diagnostics.FileVersionInfo]::GetVersionInfo($a.Location).ProductVersion;LoadContext=[Runtime.Loader.AssemblyLoadContext]::GetLoadContext($a).Name}});CompiledNewtonsoft=[ordered]@{Path=(Join-Path $BinaryRoot 'Newtonsoft.Json.dll');Sha256=(Get-FileHash (Join-Path $BinaryRoot 'Newtonsoft.Json.dll')).Hash};ActualHostNewtonsoft=[ordered]@{Path=$loaded['Newtonsoft.Json'].Location;Sha256=$HostNewtonsoftSha256;CanonicalPreloaded=$true};CanonicalForwarder=$true;LoggerAssignable=$true;LiveMutationAndCycles=$true;NativeGraphRoundTrip=$true;NativeSuite=[ordered]@{Receipt=$SuiteReceipt;Sha256=(Get-FileHash $SuiteReceipt).Hash;Total=$inner.Total;Pass=$inner.Pass};PowerShellProductModules=@(Get-Module SignalGraph,SovereignTrust.Foundation).Count}
    $result.Command=[Environment]::GetCommandLineArgs();$result.PassCount=1+$callingCases.Count;$result.FailCount=0;$result.SkipCount=0;$result.Total=1+$callingCases.Count;$result.PowerShellCallingCases=$callingCases.ToArray()
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($result|ConvertTo-Json -Depth 12));$stream=[IO.File]::Open($Receipt,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($bytes)}finally{$stream.Dispose()}
    'NATIVE HOST PASS'
}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 1}
