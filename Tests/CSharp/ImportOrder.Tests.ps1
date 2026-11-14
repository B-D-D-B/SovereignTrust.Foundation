[CmdletBinding()]
param([Parameter(Mandatory)][string]$RunRoot,
      [ValidateSet('ColdStrict','WarmRepeat','PreparedDrift','WorkerContext')][string]$Case)
$ErrorActionPreference='Stop'
if(Test-Path $RunRoot){throw 'Requires new RunRoot'}
$null=[IO.Directory]::CreateDirectory($RunRoot)
$machine=[Environment]::GetEnvironmentVariable('ST_FOUNDATION_MANIFEST','Machine')
$env:ST_FOUNDATION_MANIFEST=$machine
Remove-Item Env:ST_FOUNDATION_SELECTION_PACKET,Env:ST_FOUNDATION_SELECTION_SHA256 -ErrorAction SilentlyContinue
$caught=$null;$expected=$null;$details=$null;$origin=$null
try{
    if($Case-eq'ColdStrict'){Set-StrictMode -Version Latest}
    Import-Module -Name $machine -ErrorAction Stop
    $selection=Get-STFoundationSelection -LegacyManifest $machine
    $origin=Get-STSelectionProvenance $selection
    $prepared=$env:PSModulePath
    switch($Case){
        'WarmRepeat'{
            Import-Module $selection.SignalGraph.Manifest -ErrorAction Stop
            Import-Module $machine -ErrorAction Stop
            if($env:PSModulePath-cne$prepared-or@(Get-Module -All SignalGraph).Count-ne1-or@(Get-Module -All SovereignTrust.Foundation).Count-ne1){throw 'warm repeat changed environment/module set'}
        }
        'PreparedDrift'{
            $env:PSModulePath=$RunRoot;$expected='ST_SELECTION_DISCOVERY'
            try{& (Get-Module SovereignTrust.Foundation) {param($s) Initialize-STSelectedProcessDiscovery $s} $selection}
            finally{if($env:PSModulePath-cne$RunRoot){throw 'prepared parent repaired unexpected discovery'}}
        }
        'WorkerContext'{
            $rs=[runspacefactory]::CreateRunspace();$rs.Open();$ps=[powershell]::Create()
            try{
                $ps.Runspace=$rs
                $known=& (Get-Module SignalGraph) {[Signal].Assembly.FullName}
                $helper=Join-Path $selection.Foundation.Root 'Bootstrap/STFoundationSelection.ps1'
                $null=$ps.AddScript({param($helper,$packet,$sha,$known,$drift)
                    $global:STSelectedWorkerContext=$true
                    . $helper
                    $s=Read-STSelectionPacket $packet $sha -KnownSignalAssembly $known
                    Import-Module $s.SignalGraph.Manifest -ErrorAction Stop
                    # An owned fixture introduces drift; production must not repair it.
                    $env:PSModulePath=$drift;$errorText=$null
                    try{Initialize-STSelectedProcessDiscovery $s}catch{$errorText=$_.Exception.Message}
                    @{Error=$errorText;Path=$env:PSModulePath;Foundation=@(Get-Module SovereignTrust.Foundation).Count;Worker=$STSelectedWorkerContext}
                }.ToString()).AddArgument($helper).AddArgument($selection.PacketPath).AddArgument($selection.PacketSha256).AddArgument($known).AddArgument($RunRoot)
                $output=@($ps.Invoke());if($ps.Streams.Error.Count -gt 0){throw ($ps.Streams.Error|Out-String)}
                $details=$output[-1]
                if($details.Error-notmatch'ST_SELECTION_DISCOVERY'-or$details.Path-cne$RunRoot-or$details.Foundation-ne0-or-not$details.Worker){throw 'worker normalized discovery or failed context proof'}
            }finally{
                $ps.Dispose();$rs.Close();$rs.Dispose()
                if($env:PSModulePath-ceq$RunRoot){$env:PSModulePath=$prepared}else{throw 'fixture state drift; conditional process restore withheld'}
            }
        }
    }
    if($expected){throw 'Expected rejection absent'}
}catch{$caught=$_.Exception.Message}
$pass=if($expected){$caught-match$expected}else{$null-eq$caught}
if([Environment]::GetEnvironmentVariable('ST_FOUNDATION_MANIFEST','Machine')-cne$machine){$pass=$false}
$result=[ordered]@{Case=$Case;Pass=$pass;Expected=$expected;Observed=$caught;Origin=$origin;Details=$details;MachineUnchanged=$true}
[IO.File]::WriteAllText((Join-Path $RunRoot 'receipt.json'),($result|ConvertTo-Json -Depth 12))
$result|ConvertTo-Json -Depth 12
if(-not$pass){exit 1}
