param([Parameter(Mandatory)][string]$BinaryRoot,[Parameter(Mandatory)][string]$Receipt,
      [Parameter(Mandatory)][string]$HostNewtonsoftSha256,[Parameter(Mandatory)][string]$Inputs,
      [Parameter(Mandatory)][string]$Catalog,[Parameter(Mandatory)][string]$SuiteReceipt)
$ErrorActionPreference='Stop'
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
    $s=[SignalGraph.Signal]::Named('native-host',$null)
    $g=[SignalGraph.Graph]::Start('native-host',$null,$false).Result
    $s.Pointer=$g;$s.Jacket=$s;$s.Control=$s;$s.Result=@{Value=$false}
    $null=$g.RegisterSignal('Member',$s)
    $g.Grid['member'].Result.Value=$true
    if(-not [object]::ReferenceEquals($g.Grid['MEMBER'],$s) -or -not [object]::ReferenceEquals($s.Pointer,$g) -or -not [object]::ReferenceEquals($s.Jacket,$s) -or -not [object]::ReferenceEquals($s.Control,$s) -or $s.Result.Value -ne $true){throw 'ST_NATIVE_LIVE_IDENTITY'}
    $serialized=$g.ToJson($false);$op=[SignalGraph.Graph]::FromJson($serialized,$false)
    if($op.Failure -or -not [object]::ReferenceEquals($op.Result.Grid['Member'].Pointer,$op.Result)){throw 'ST_NATIVE_GRAPH_ROUNDTRIP'}
    $contract=$loaded['Microsoft.Extensions.Logging.Abstractions'].GetType('Microsoft.Extensions.Logging.ILogger',$true)
    if(-not $contract.IsAssignableFrom($type)){throw 'ST_NATIVE_LOGGER_TYPE_IDENTITY'}
    $suite=[Reflection.Assembly]::LoadFrom((Join-Path $BinaryRoot 'SovereignTrust.Foundation.ParityTests.dll'))
    $arguments=[object[]]::new(1);$arguments[0]=[string[]]@('--wave','1','--receipt',$SuiteReceipt,'--inputs',$Inputs,'--catalog',$Catalog)
    $suiteExit=$suite.EntryPoint.Invoke($null,$arguments)
    if($suiteExit -ne 0){throw "ST_NATIVE_HOST_SUITE: exit$suiteExit"}
    $inner=Get-Content -LiteralPath $SuiteReceipt -Raw|ConvertFrom-Json
    if(-not $inner.Pass -or $inner.Total -ne 33 -or $inner.FailCount -ne 0){throw 'ST_NATIVE_HOST_SUITE_INVENTORY'}
    $jsonBinding=@($inner.Assemblies|Where-Object{$_.FullName.StartsWith('Newtonsoft.Json,')})
    if($jsonBinding.Count -ne 1 -or $jsonBinding[0].File.Path -cne $loaded['Newtonsoft.Json'].Location -or [Newtonsoft.Json.Linq.JObject].Assembly -ne $loaded['Newtonsoft.Json'] -or [Newtonsoft.Json.JsonException].Assembly -ne $loaded['Newtonsoft.Json'] -or @([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object{$_.GetName().Name -eq 'Newtonsoft.Json'}).Count -ne 1){throw 'ST_NATIVE_JSON_TYPE_IDENTITY'}
    $result=[ordered]@{Pass=$true;Scope='PS7.6 native-only explicit assembly/type/live graph load and complete native case vector; no hybrid substitution';PowerShell=$PSVersionTable.PSVersion.ToString();Runtime=[Environment]::Version.ToString();Architecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString();Assemblies=@($names|ForEach-Object{$a=$loaded[$_];[ordered]@{Name=$a.FullName;Path=$a.Location;Sha256=(Get-FileHash $a.Location).Hash;ProductVersion=[Diagnostics.FileVersionInfo]::GetVersionInfo($a.Location).ProductVersion;LoadContext=[Runtime.Loader.AssemblyLoadContext]::GetLoadContext($a).Name}});CompiledNewtonsoft=[ordered]@{Path=(Join-Path $BinaryRoot 'Newtonsoft.Json.dll');Sha256=(Get-FileHash (Join-Path $BinaryRoot 'Newtonsoft.Json.dll')).Hash};ActualHostNewtonsoft=[ordered]@{Path=$loaded['Newtonsoft.Json'].Location;Sha256=$HostNewtonsoftSha256;CanonicalPreloaded=$true};CanonicalForwarder=$true;LoggerAssignable=$true;LiveMutationAndCycles=$true;NativeGraphRoundTrip=$true;NativeSuite=[ordered]@{Receipt=$SuiteReceipt;Sha256=(Get-FileHash $SuiteReceipt).Hash;Total=$inner.Total;Pass=$inner.Pass};PowerShellProductModules=@(Get-Module SignalGraph,SovereignTrust.Foundation).Count}
    $result.Command=[Environment]::GetCommandLineArgs();$result.PassCount=1;$result.FailCount=0;$result.SkipCount=0
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($result|ConvertTo-Json -Depth 12));$stream=[IO.File]::Open($Receipt,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($bytes)}finally{$stream.Dispose()}
    'NATIVE HOST PASS'
}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 1}
