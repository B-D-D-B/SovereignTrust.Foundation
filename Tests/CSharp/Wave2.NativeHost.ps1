param([Parameter(Mandatory)][string]$NativeDirectory,[Parameter(Mandatory)][string]$Receipt,[switch]$Deliberate)
$ErrorActionPreference='Stop'
if(Test-Path $Receipt){throw 'Host receipt must be new'}
if($PSVersionTable.PSVersion.Major -ne 7 -or $PSVersionTable.PSVersion.Minor -ne 6){throw 'Wave2 host requires PS7.6'}
if(@(Get-Module -All SovereignTrust.Foundation,SignalGraph).Count){throw 'Native component host must contain no PS product modules'}
$hostNewtonsoft=[Newtonsoft.Json.JsonConvert].Assembly
$expectedNewtonsoft=Join-Path $PSHOME Newtonsoft.Json.dll
if($hostNewtonsoft.Location -ne $expectedNewtonsoft -or -not [object]::ReferenceEquals([Runtime.Loader.AssemblyLoadContext]::GetLoadContext($hostNewtonsoft),[Runtime.Loader.AssemblyLoadContext]::Default)){throw 'Unexpected host Newtonsoft origin/context'}
foreach($name in 'Microsoft.Extensions.Logging.Abstractions.dll','SignalGraph.dll','SovereignTrust.Foundation.dll','SovereignTrust.Foundation.Wave2Tests.dll'){
    $path=Join-Path $NativeDirectory $name
    $identity=[Reflection.AssemblyName]::GetAssemblyName($path).FullName
    $loaded=@([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object FullName -CEQ $identity)
    if($loaded.Count){if($loaded.Count -ne 1 -or $loaded[0].Location -ne $path -or -not [object]::ReferenceEquals([Runtime.Loader.AssemblyLoadContext]::GetLoadContext($loaded[0]),[Runtime.Loader.AssemblyLoadContext]::Default)){throw "Host identity collision: $name"}}
    else{[void][Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath($path)}
}
$binding=[ordered]@{PowerShell=$PSVersionTable.PSVersion.ToString();Runtime=[Environment]::Version.ToString();Command=[Environment]::GetCommandLineArgs();HostNewtonsoft=[ordered]@{Path=$hostNewtonsoft.Location;Identity=$hostNewtonsoft.FullName;Sha256=(Get-FileHash $hostNewtonsoft.Location).Hash;FileVersion=(Get-Item $hostNewtonsoft.Location).VersionInfo.FileVersion;LoadContext=[Runtime.Loader.AssemblyLoadContext]::GetLoadContext($hostNewtonsoft).Name};CompiledPackageNewtonsoft=[ordered]@{Path=(Join-Path $NativeDirectory Newtonsoft.Json.dll);Sha256=(Get-FileHash (Join-Path $NativeDirectory Newtonsoft.Json.dll)).Hash;FileVersion=(Get-Item (Join-Path $NativeDirectory Newtonsoft.Json.dll)).VersionInfo.FileVersion;Loaded=$false};PSProductModules=@(Get-Module -All SovereignTrust.Foundation,SignalGraph).Count}
$binding|ConvertTo-Json -Depth 10|Set-Content ($Receipt+'.binding.json') -Encoding utf8NoBOM
$code=[Wave2Suite]::Run($Receipt,[bool]$Deliberate)
if(@(Get-Module -All SovereignTrust.Foundation,SignalGraph).Count){throw 'Native component host imported a PS product module'}
exit $code
