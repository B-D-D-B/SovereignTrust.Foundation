[CmdletBinding()]
param([Parameter(Mandatory)][string]$RunRoot,
      [Parameter(Mandatory)][string]$SelectionPacket,
      [Parameter(Mandatory)][string]$SelectionPacketSha256,
      [string]$Case,[string]$OtherPacket,[string]$OtherPacketSha256)
$ErrorActionPreference='Stop'
$helper=[IO.Path]::GetFullPath("$PSScriptRoot/../../Src/PowerShell/Bootstrap/STFoundationSelection.ps1")
. $helper
function Assert-SelectionTest([bool]$Condition,[string]$Message) { if (-not $Condition) { throw "ASSERTION: $Message" } }
if ($Case) {
    $discovery=Get-Content $SelectionPacket -Raw|ConvertFrom-Json -Depth 30
    $env:PSModulePath=Get-STSelectedDiscoveryPath $discovery
    $fixture=Join-Path $RunRoot 'fixture-effect.txt'
    $before=@(Get-Module SovereignTrust.Foundation).Count
    $expected=$null;$caught=$null;$extra=$null
    $rejectionDiscovery=$env:PSModulePath
    try {
        switch -Wildcard ($Case) {
            'Blank' { $env:ST_FOUNDATION_MANIFEST=''; $expected='ST_SELECTION_BLANK|ST_SELECTION_STATE'; $selection=Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256; Get-STFoundationSelection $selection.Foundation.Manifest -SelectionPacket $selection -SelectionState Present }
            'Relative' { $env:ST_FOUNDATION_MANIFEST='./Foundation.psd1';$expected='ST_SELECTION_PATH';$selection=Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256;Get-STFoundationSelection $selection.Foundation.Manifest -SelectionPacket $selection }
            'Missing' { $env:ST_FOUNDATION_MANIFEST=Join-Path $RunRoot 'missing.psd1';$expected='Cannot find path|does not exist';$selection=Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256;Get-STFoundationSelection $selection.Foundation.Manifest -SelectionPacket $selection }
            'WrongModule' { $selection=Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256;$env:ST_FOUNDATION_MANIFEST=$selection.SignalGraph.Manifest;$expected='ST_SELECTION_MODULE';Get-STFoundationSelection $selection.Foundation.Manifest -SelectionPacket $selection }
            'HashMismatch' { $expected='ST_SELECTION_HASH';Read-STSelectionPacket $SelectionPacket ('0'*64) }
            'MalformedPacket' { $path=Join-Path $RunRoot 'malformed.json';[IO.File]::WriteAllText($path,'{bad');$expected='Conversion from JSON failed';Read-STSelectionPacket $path (Get-FileHash $path).Hash }
            'MissingDependency' { $s=Get-Content $SelectionPacket -Raw|ConvertFrom-Json -Depth 30;$s.SignalGraph.Manifest=Join-Path $RunRoot 'missing/SignalGraph.psd1';$expected='Cannot find path|does not exist';Assert-STFoundationSelection $s }
            'WrongDependency' { $s=Get-Content $SelectionPacket -Raw|ConvertFrom-Json -Depth 30;$s.SignalGraph.Guid=[guid]::Empty.ToString();$expected='ST_SELECTION_MODULE';Assert-STFoundationSelection $s }
            'MemberDrift' { $s=Get-Content $SelectionPacket -Raw|ConvertFrom-Json -Depth 30;$s.Foundation.Files[0].Sha256='0'*64;$expected='ST_SELECTION_HASH';Assert-STFoundationSelection $s }
            'WrongPreloaded' { $m=New-Module -Name SignalGraph -ScriptBlock {};Import-Module $m;$expected='ST_SELECTION_LOADED';Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256 }
            'DuplicatePreloaded' {
                foreach ($version in @('1.0.0','2.0.0')) {
                    $dir=Join-Path $RunRoot $version;$null=[IO.Directory]::CreateDirectory($dir)
                    [IO.File]::WriteAllText((Join-Path $dir 'SignalGraph.psm1'),"`$script:SelectionFixtureOnly=`$true")
                    [IO.File]::WriteAllText((Join-Path $dir 'SignalGraph.psd1'),"@{RootModule='SignalGraph.psm1';ModuleVersion='$version';GUID='40b7332d-7c4e-4349-a89a-03b29b258238'}")
                    Import-Module (Join-Path $dir 'SignalGraph.psd1')
                }
                $extra=@(Get-Module -All SignalGraph).Count
                Assert-SelectionTest ($extra -eq 2) 'duplicate fixture did not preload two versions'
                $expected='ST_SELECTION_DUPLICATE';Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256
            }
            'UnknownType' { Add-Type 'namespace SignalGraph { public class Signal {} }';$expected='ST_SELECTION_TYPE';Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256 }
            'TypeAliasCollision' {
                $api=[psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
                $api::Add('MappedTokenAdapter',[string])
                $selection=Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256
                $expected='ST_SELECTION_TYPE_ALIAS'
                try { Import-STSelectedFoundation $selection } finally {
                    Assert-SelectionTest ([object]::ReferenceEquals($api::Get['MappedTokenAdapter'],[string])) 'collision alias was overwritten'
                }
            }
            'SessionAliasCollision' {
                $api=[psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
                $api::Add('MappedSessionAdapter',[string])
                $selection=Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256
                $expected='ST_SELECTION_TYPE_ALIAS'
                try { Import-STSelectedFoundation $selection } finally {
                    Assert-SelectionTest ([object]::ReferenceEquals($api::Get['MappedSessionAdapter'],[string])) 'Session collision alias overwritten'
                    Assert-SelectionTest (-not $api::Get.ContainsKey('MappedTokenAdapter')) 'Token alias added before complete preflight'
                }
            }
            'SessionTypeAlias' {
                $selection=Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256
                Import-STSelectedFoundation $selection
                $manifest=[IO.Path]::GetFullPath("$PSScriptRoot/../../../SovereignTrust.Adapters/Src/Session/ST/PowerShell/Session_ST.psd1")
                Import-Module $manifest -ErrorAction Stop
                $expectedType=& (Get-Module SovereignTrust.Foundation) { [MappedSessionAdapter] }
                $adapterType=& (Get-Module Session_ST) { [Session_ST] }
                Assert-SelectionTest ([object]::ReferenceEquals($adapterType.GetProperty('MappedAdapter').PropertyType,$expectedType)) 'Session property Type changed'
                $constructor=@($adapterType.GetConstructors()|Where-Object {$_.GetParameters().Count -eq 1})[0]
                Assert-SelectionTest ([object]::ReferenceEquals($constructor.GetParameters()[0].ParameterType,$expectedType)) 'Session constructor Type changed'
                $instance=$constructor.Invoke(@($expectedType.GetConstructor([type[]]@()).Invoke(@())))
                Assert-SelectionTest ([object]::ReferenceEquals($instance.MappedAdapter.GetType(),$expectedType)) 'Session constructor changed type'
                Import-STSelectedFoundation $selection
                $api=[psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
                Assert-SelectionTest ([object]::ReferenceEquals($api::Get['MappedSessionAdapter'],$expectedType)) 'repeat selection replaced Session alias'
                $extra=[ordered]@{Type=$expectedType.AssemblyQualifiedName;Property=$adapterType.GetProperty('MappedAdapter').PropertyType.AssemblyQualifiedName;OriginalManifest=$manifest;RepeatReferenceUnchanged=$true}
            }
            'TokenTypeAlias' {
                $selection=Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256
                Import-STSelectedFoundation $selection
                $manifest=[IO.Path]::GetFullPath("$PSScriptRoot/../../../SDAFusion.Adapters/Src/Token/SDA/PowerShell/Token_SDA.psd1")
                Import-Module $manifest -ErrorAction Stop
                $expectedType=& (Get-Module SovereignTrust.Foundation) { [MappedTokenAdapter] }
                $tokenType=& (Get-Module Token_SDA) { [Token_SDA] }
                Assert-SelectionTest ([object]::ReferenceEquals($tokenType.GetProperty('MappedAdapter').PropertyType,$expectedType)) 'Token property Type changed'
                $constructor=@($tokenType.GetConstructors()|Where-Object {$_.GetParameters().Count -eq 1})[0]
                Assert-SelectionTest ([object]::ReferenceEquals($constructor.GetParameters()[0].ParameterType,$expectedType)) 'Token constructor Type changed'
                $instance=$constructor.Invoke(@($expectedType.GetConstructor([type[]]@()).Invoke(@())))
                Assert-SelectionTest ([object]::ReferenceEquals($instance.MappedAdapter.GetType(),$expectedType)) 'Token constructor did not retain selected class'
                Import-STSelectedFoundation $selection
                $api=[psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
                Assert-SelectionTest ([object]::ReferenceEquals($api::Get['MappedTokenAdapter'],$expectedType)) 'repeat selection replaced Type alias'
                $extra=[ordered]@{Type=$expectedType.AssemblyQualifiedName;Property=$tokenType.GetProperty('MappedAdapter').PropertyType.AssemblyQualifiedName;OriginalManifest=$manifest;RepeatReferenceUnchanged=$true}
            }
            'WorkerMismatch' {
                $selection=Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256
                Import-STSelectedFoundation $selection
                $wrong=Get-Content $OtherPacket -Raw|ConvertFrom-Json -Depth 30
                $expected='ST_SELECTION_WORKER_MISMATCH'
                Get-STWorkerSelection -FoundationModulePath $wrong.Foundation.Manifest
            }
            'DiscoveryDrift' {
                $selection=Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256
                Import-STSelectedFoundation $selection
                $env:PSModulePath=$RunRoot
                $expected='ST_SELECTION_DISCOVERY'
                try { $worker=New-STSelectedRunspace $selection; $worker.Dispose() } finally {
                    Assert-SelectionTest ($env:PSModulePath -ceq $RunRoot) 'worker changed drifting process environment'
                }
            }
            'LegacyAbsent' {
                Remove-Item Env:ST_FOUNDATION_MANIFEST
                Remove-Item Env:ST_FOUNDATION_SELECTION_PACKET
                $selection=Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256
                Initialize-STSelectedDependency $selection
                $legacy=Get-STFoundationSelection -LegacyManifest $selection.Foundation.Manifest -SelectionState Absent
                Assert-SelectionTest ($legacy.Schema -eq 'ST.Foundation.Legacy/1') 'legacy fallback contract'
                Import-STSelectedFoundation $legacy
                $extra=Get-STSelectionProvenance $selection
            }
            'WorkerStartup' {
                $selection=Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256
                Import-STSelectedFoundation $selection
                $state=New-STSelectedInitialSessionState $selection
                $pool=[runspacefactory]::CreateRunspacePool(1,2,$state,$Host)
                $pool.Open();$ps=[powershell]::Create()
                try {
                    $ps.RunspacePool=$pool
                    $null=$ps.AddScript('Assert-STFoundationSelection -Selection $STWorkerSelection -RequireLoaded; $STWorkerProvenance')
                    $output=@($ps.Invoke());if($ps.HadErrors){throw ($ps.Streams.Error|Out-String)}
                    Assert-SelectionTest ($output.Count -eq 1 -and $output[0].FoundationPath -eq (Join-Path $selection.Foundation.Root 'SovereignTrust.Foundation.psm1')) 'actual InitialSessionState worker startup provenance'
                    $extra=$output[0]
                } finally { $ps.Dispose();$pool.Close();$pool.Dispose() }
            }
            'AdapterImports*' {
                $selection=Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256
                Import-STSelectedFoundation $selection
                $adapters=@(Get-Content "$PSScriptRoot/Fixtures/production-loaders.json" -Raw|ConvertFrom-Json)
                Assert-SelectionTest ($adapters.Count -eq 15) 'production loader membership'
                $loaded=@()
                $offset=[int]($Case -replace '^AdapterImports','')
                foreach($adapter in @($adapters|Select-Object -Skip $offset -First 5)) {
                    $manifest=[IO.Path]::GetFullPath((Join-Path "$PSScriptRoot/Fixtures" $adapter.Manifest))
                    $index=$offset+$loaded.Count
                    [IO.File]::WriteAllText((Join-Path $RunRoot ("adapter-$index.started.json")),(@{Manifest=$manifest;StartedUtc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json))
                    Assert-STSelectedEntryPoint -Selection $selection -EntryPoint $manifest
                    Import-Module -Name $manifest -ErrorAction Stop
                    Assert-STFoundationSelection $selection -RequireLoaded
                    $loaded+=$manifest
                    [IO.File]::WriteAllText((Join-Path $RunRoot ("adapter-$index.completed.json")),(@{Manifest=$manifest;Pass=$true;Origin=Get-STSelectionProvenance $selection}|ConvertTo-Json -Depth 10))
                }
                $extra=$loaded
            }
            default { throw "Unknown case $Case" }
        }
        if ($expected) { [IO.File]::WriteAllText($fixture,'unexpected fixture execution');throw 'ASSERTION: expected rejection did not occur' }
    } catch { $caught=$_.Exception.Message }
    $pass=if($expected){$null -ne $caught -and $caught -match $expected -and -not(Test-Path $fixture)}else{$null -eq $caught}
    if ($Case -in @('WrongPreloaded','DuplicatePreloaded','UnknownType') -and $env:PSModulePath -cne $rejectionDiscovery) { $pass=$false }
    $receipt=[ordered]@{Case=$Case;Pass=$pass;Expected=$expected;Observed=$caught;FixtureEffects=[int](Test-Path $fixture);FoundationBefore=$before;FoundationAfter=@(Get-Module SovereignTrust.Foundation).Count;Extra=$extra;PID=$PID;PowerShell=$PSVersionTable.PSVersion.ToString();Runtime=[Environment]::Version.ToString();PacketSha256=$SelectionPacketSha256}
    $receipt.DiscoveryBefore=$rejectionDiscovery
    $receipt.DiscoveryAfter=$env:PSModulePath
    [IO.File]::WriteAllText((Join-Path $RunRoot 'receipt.json'),($receipt|ConvertTo-Json -Depth 10))
    if(-not $pass){[Console]::Error.WriteLine(($receipt|ConvertTo-Json -Compress -Depth 10));exit 1};exit 0
}
if(-not[IO.Path]::IsPathFullyQualified($RunRoot)-or(Test-Path $RunRoot)){throw 'Requires new absolute suite RunRoot'}
$null=[IO.Directory]::CreateDirectory($RunRoot)
$original=[Environment]::GetEnvironmentVariable('ST_FOUNDATION_MANIFEST','Process')
$selection=Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256
$results=@()
foreach($name in @('Blank','Relative','Missing','WrongModule','HashMismatch','MalformedPacket','MissingDependency','WrongDependency','MemberDrift','WrongPreloaded','DuplicatePreloaded','UnknownType','TypeAliasCollision','TokenTypeAlias','SessionAliasCollision','SessionTypeAlias','WorkerMismatch','LegacyAbsent','WorkerStartup','AdapterImports0','AdapterImports5','AdapterImports10')) {
    $dir=Join-Path $RunRoot $name;$null=[IO.Directory]::CreateDirectory($dir)
    $start=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'))
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    foreach($arg in @('-NoLogo','-NoProfile','-File',$PSCommandPath,'-RunRoot',$dir,'-SelectionPacket',$SelectionPacket,'-SelectionPacketSha256',$SelectionPacketSha256,'-Case',$name,'-OtherPacket',[string]$OtherPacket,'-OtherPacketSha256',[string]$OtherPacketSha256)){$start.ArgumentList.Add($arg)}
    $start.Environment['ST_FOUNDATION_MANIFEST']=$selection.Foundation.Manifest
    $start.Environment['ST_FOUNDATION_SELECTION_PACKET']=$SelectionPacket
    $start.Environment['ST_FOUNDATION_SELECTION_SHA256']=$SelectionPacketSha256
    $start.Environment['PSModulePath']=(Split-Path $selection.SignalGraph.Root)+[IO.Path]::PathSeparator+(Join-Path $PSHOME 'Modules')
    $process=[Diagnostics.Process]::Start($start)
    try {
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(120000)){
            $process.Kill($true);$process.WaitForExit()
            [IO.File]::WriteAllText((Join-Path $dir 'receipt.json'),(@{Case=$name;Pass=$false;Observed="Timeout $name";OwnedChildStopped=$true}|ConvertTo-Json))
        }
        [IO.File]::WriteAllText((Join-Path $dir 'stdout.txt'),$stdout.GetAwaiter().GetResult())
        [IO.File]::WriteAllText((Join-Path $dir 'stderr.txt'),$stderr.GetAwaiter().GetResult())
        $receipt=Get-Content (Join-Path $dir 'receipt.json') -Raw|ConvertFrom-Json -Depth 20
        $results+=[ordered]@{Case=$name;Pass=$receipt.Pass -and $process.ExitCode -eq 0;Receipt=Join-Path $dir 'receipt.json'}
    } finally {$process.Dispose()}
}
Assert-SelectionTest ([Environment]::GetEnvironmentVariable('ST_FOUNDATION_MANIFEST','Process') -ceq $original) 'parent environment changed'
$pass=@($results|Where-Object Pass).Count
$summary=[ordered]@{Pass=$pass;Fail=$results.Count-$pass;Total=$results.Count;ParentEnvironmentUnchanged=$true;Results=$results}
[IO.File]::WriteAllText((Join-Path $RunRoot 'summary.json'),($summary|ConvertTo-Json -Depth 10))
$summary|ConvertTo-Json -Depth 10
if($summary.Fail){exit 1}
