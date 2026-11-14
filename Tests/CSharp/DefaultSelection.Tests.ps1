[CmdletBinding()]
param([Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][string]$NormalPacket,
      [Parameter(Mandatory)][string]$CandidatePacket,[Parameter(Mandatory)][string]$CandidateSha256,
      [ValidateSet('NormalFirst','AdapterFirst','BOverride','DefaultMismatch','BadDefaultHash','LegacyAbsent')][string]$Case)
$ErrorActionPreference='Stop'
if(Test-Path $RunRoot){throw 'Requires new RunRoot'}
$null=[IO.Directory]::CreateDirectory($RunRoot)
$machine=[Environment]::GetEnvironmentVariable('ST_FOUNDATION_MANIFEST','Machine')
$user=[Environment]::GetEnvironmentVariable('ST_FOUNDATION_MANIFEST','User')
$env:ST_FOUNDATION_MANIFEST=$machine
Remove-Item Env:ST_FOUNDATION_SELECTION_PACKET,Env:ST_FOUNDATION_SELECTION_SHA256 -ErrorAction SilentlyContinue
$adapter=[IO.Path]::GetFullPath("$PSScriptRoot/../../../SDAFusion.Adapters/Src/Token/SDA/PowerShell/Token_SDA.psd1")
$sentinel=Join-Path $RunRoot 'unexpected-effect.txt'
$expected=$null;$caught=$null;$origin=$null;$workerOrigin=$null
try {
    switch($Case){
        'NormalFirst' { Import-Module -Name $machine -ErrorAction Stop;Import-Module -Name $adapter -ErrorAction Stop }
        'AdapterFirst' { Import-Module -Name $adapter -ErrorAction Stop }
        'BOverride' {
            $candidate=Get-Content $CandidatePacket -Raw|ConvertFrom-Json -Depth 30
            $env:ST_FOUNDATION_MANIFEST=$candidate.Foundation.Manifest
            $env:ST_FOUNDATION_SELECTION_PACKET=$CandidatePacket
            $env:ST_FOUNDATION_SELECTION_SHA256=$CandidateSha256
            Import-Module -Name $candidate.Foundation.Manifest -ErrorAction Stop
            Import-Module -Name $adapter -ErrorAction Stop
        }
        'DefaultMismatch' {
            $candidate=Get-Content $CandidatePacket -Raw|ConvertFrom-Json -Depth 30
            $env:ST_FOUNDATION_MANIFEST=$candidate.Foundation.Manifest
            $expected='ST_SELECTION_DEFAULT';Import-Module $adapter -ErrorAction Stop
        }
        'BadDefaultHash' {
            $fixture=Join-Path $RunRoot 'trusted-fixture';$bootstrap=Join-Path $fixture 'Src/PowerShell/Bootstrap'
            $null=[IO.Directory]::CreateDirectory($bootstrap)
            Copy-Item "$PSScriptRoot/../../Src/PowerShell/Bootstrap/STFoundationSelection.ps1" (Join-Path $bootstrap 'STFoundationSelection.ps1')
            [IO.File]::WriteAllText((Join-Path $fixture 'STFoundation.DefaultSelection.json'),(@{Schema='ST.Foundation.DefaultSelection/1';FoundationManifest=$machine;PacketPath=$NormalPacket;PacketSha256='0'*64}|ConvertTo-Json))
            . (Join-Path $bootstrap 'STFoundationSelection.ps1')
            $expected='ST_SELECTION_HASH';$null=Get-STFoundationSelection -LegacyManifest $machine
        }
        'LegacyAbsent' {
            Remove-Item Env:ST_FOUNDATION_MANIFEST
            Import-Module -Name $machine -ErrorAction Stop
            $legacy=Get-STFoundationSelection -LegacyManifest $machine -SelectionState Absent
            if($legacy.Schema -ne 'ST.Foundation.Legacy/1' -or @(Get-Module -All SignalGraph).Count-ne1){throw 'legacy dependency behavior changed'}
            $origin=@{Foundation=(Get-Module SovereignTrust.Foundation).Path;SignalGraph=(Get-Module SignalGraph).Path;Legacy=$true}
        }
    }
    if($expected){[IO.File]::WriteAllText($sentinel,'unexpected');throw 'expected failure absent'}
    if($Case -ne 'LegacyAbsent'){
        # No packet or helper was supplied before the actual original import.
        $selection=Get-STFoundationSelection -LegacyManifest $machine
        $reviewed=Get-Content $(if($Case-eq'BOverride'){$CandidatePacket}else{$NormalPacket}) -Raw|ConvertFrom-Json -Depth 30
        if((Get-Module SovereignTrust.Foundation).ModuleBase-ne$reviewed.Foundation.Root-or(Get-Module SignalGraph).ModuleBase-ne$reviewed.SignalGraph.Root){throw 'wrong default/override module origin'}
        if($Case-ne'BOverride'-and$selection.DefaultDescriptor-ne[IO.Path]::GetFullPath("$PSScriptRoot/../../STFoundation.DefaultSelection.json")){throw 'normal default did not use trusted descriptor'}
        $origin=Get-STSelectionProvenance $selection
        $discovery=$env:PSModulePath
        $worker=New-STSelectedRunspace $selection
        try{$workerOrigin=$worker.STSelectionProvenance}finally{$worker.Close();$worker.Dispose()}
        if($workerOrigin.FoundationPath-ne$origin.FoundationPath-or$workerOrigin.SignalGraphPath-ne$origin.SignalGraphPath-or$discovery-cne$env:PSModulePath){throw 'default worker provenance/environment mismatch'}
    }
}catch{$caught=$_.Exception.Message}
$modules=@(Get-Module -All SignalGraph,SovereignTrust.Foundation)
$signalTypes=@([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object{$null-ne$_.GetType('Signal',$false)-or$null-ne$_.GetType('SignalGraph.Signal',$false)})
$pass=if($expected){$caught-match$expected-and$modules.Count-eq0-and$signalTypes.Count-eq0-and-not(Test-Path $sentinel)}else{$null-eq$caught}
$machineAfter=[Environment]::GetEnvironmentVariable('ST_FOUNDATION_MANIFEST','Machine')
$userAfter=[Environment]::GetEnvironmentVariable('ST_FOUNDATION_MANIFEST','User')
if($machineAfter-cne$machine-or$userAfter-cne$user){$pass=$false;$caught='external default/user scope drift'}
$result=[ordered]@{Case=$Case;Pass=$pass;Expected=$expected;Observed=$caught;Root=$origin;Worker=$workerOrigin;WorkerDisposed=$null-ne$workerOrigin;MachineBefore=$machine;MachineAfter=$machineAfter;UserUnchanged=$userAfter-ceq$user;AgentMachineWrites=0;AgentRollback='N/A - user-owned setting';NegativeModules=if($expected){$modules.Count}else{$null};NegativeSignalAssemblies=if($expected){$signalTypes.Count}else{$null};FixtureEffects=[int](Test-Path $sentinel)}
[IO.File]::WriteAllText((Join-Path $RunRoot 'receipt.json'),($result|ConvertTo-Json -Depth 12))
$result|ConvertTo-Json -Depth 12
if(-not$pass){exit 1}
