[CmdletBinding()]
param([Parameter(Mandatory)][string]$SelectionPacket,[Parameter(Mandatory)][string]$SelectionPacketSha256,
      [Parameter(Mandatory)][string]$RunRoot)
$ErrorActionPreference='Stop'
if(Test-Path $RunRoot){throw 'Requires new RunRoot'}
$null=[IO.Directory]::CreateDirectory($RunRoot)
. "$PSScriptRoot/../../Src/PowerShell/Bootstrap/STFoundationSelection.ps1"
$selection=Read-STSelectionPacket $SelectionPacket $SelectionPacketSha256
$env:ST_FOUNDATION_MANIFEST=$selection.Foundation.Manifest
$env:ST_FOUNDATION_SELECTION_PACKET=$SelectionPacket
$env:ST_FOUNDATION_SELECTION_SHA256=$SelectionPacketSha256
$env:PSModulePath=Get-STSelectedDiscoveryPath $selection
$discoveryBeforeWorkers=$env:PSModulePath
Import-STSelectedFoundation $selection
$available=@(Get-Module -ListAvailable SignalGraph|ForEach-Object {
    $rootModule=Join-Path $_.ModuleBase 'SignalGraph.psm1'
    [ordered]@{Path=$_.Path;ModuleBase=$_.ModuleBase;Version=$_.Version.ToString();ManifestSha256=(Get-FileHash $_.Path).Hash;RootModule=$rootModule;RootSha256=(Get-FileHash $rootModule).Hash}
})
$expectedType=& (Get-Module SignalGraph) { [Signal] }
$beforeNamed=@(Get-Module -All SignalGraph|ForEach-Object Path)
$actualNamed=& ([scriptblock]::Create('using module SignalGraph; [Signal]'))
$afterNamed=@(Get-Module -All SignalGraph|ForEach-Object Path)
if(-not[object]::ReferenceEquals($actualNamed,$expectedType)-or($beforeNamed-join '|')-cne($afterNamed-join '|')){throw 'Named dependency mapping failed'}
[IO.File]::WriteAllText((Join-Path $RunRoot 'named-discovery.json'),(@{Available=$available;SelectedType=$actualNamed.AssemblyQualifiedName;SameTypeReference=$true;LoadedBefore=$beforeNamed;LoadedAfter=$afterNamed;Discovery=$env:PSModulePath}|ConvertTo-Json -Depth 10))
$module=Get-Module SovereignTrust.Foundation
$fixture=Join-Path $RunRoot 'LocalWorkers.ps1'
$escaped=$RunRoot.Replace("'","''")
$fixtureCode=@'
using module SignalGraph
$marker=Join-Path '__ROOT__' ([guid]::NewGuid().ToString()+'.worker.json')
[IO.File]::WriteAllText($marker,(@{Tag=$STSelectionTestTag;Provenance=$STWorkerProvenance;WorkerContext=$STSelectedWorkerContext}|ConvertTo-Json -Depth 10))
function global:Initialize-STEnvironment {
    param($Environment)
    $signal=[Signal]::Start('LocalSelectionInitialization')
    $signal.SetResult([pscustomobject]@{LocalOnly=$true})
    return $signal
}
function global:Test-STSelectionWorker {
    param($Runtime,$WorkItem,$Context)
    $signal=[Signal]::Start('LocalSelectionWorker')
    $signal.SetResult($STWorkerProvenance)
    return $signal
}
'@
[IO.File]::WriteAllText($fixture,$fixtureCode.Replace('__ROOT__',$escaped))
# Retain the actual production factory, adding only a local no-provider fixture
# after its complete selection/import/provenance startup has succeeded.
& $module {
    param($fixture)
    $script:STSelectionOriginalFactory=(Get-Command New-STSelectedInitialSessionState).ScriptBlock
    $script:STSelectionTestFixture=$fixture
    function script:New-STSelectedInitialSessionState {
        param($Selection)
        $state=& $script:STSelectionOriginalFactory $Selection
        $state.Variables.Add([Management.Automation.Runspaces.SessionStateVariableEntry]::new('STSelectionTestTag',$script:STSelectionTestTag,'Local selection fixture'))
        $null=$state.StartupScripts.Add($script:STSelectionTestFixture)
        return $state
    }
} $fixture
$results=@()
function Assert-Worker([bool]$Condition,[string]$Message){if(-not $Condition){throw "ASSERTION: $Message"}}
try {
    $signal=& (Get-Module SignalGraph) { [Signal]::Start('SelectionWorkerChecks') }
    & $module { $script:STSelectionTestTag='Pool' }
    $poolResult=Invoke-STRunspacePool -Signal $signal -EnvironmentDefinition ([pscustomobject]@{LocalOnly=$true}) `
        -WorkItems @([pscustomobject]@{Index=0},[pscustomobject]@{Index=1}) -WorkerCommand Test-STSelectionWorker -ThrottleLimit 2
    Assert-Worker ($poolResult.HasResult() -and -not $poolResult.Failure()) "actual pool failed: $($poolResult.Entries.Message -join ' | ')"
    foreach($item in @($poolResult.GetResult())) {
        Assert-Worker ($item.SelectionProvenance.FoundationPath -eq (Join-Path $selection.Foundation.Root 'SovereignTrust.Foundation.psm1')) 'pool worker selected wrong root'
        Assert-Worker ($item.WorkerSignal.Result.PacketSha256 -eq $selection.PacketSha256) 'pool worker packet mismatch'
    }
    $results+=[ordered]@{Case='ActualRunspacePool';Pass=$true;Workers=2}
    & $module { $script:STSelectionTestTag='Background' }
    $task=Start-STBackgroundTask -Signal $signal -EnvironmentDefinition ([pscustomobject]@{LocalOnly=$true}) `
        -WorkItem ([pscustomobject]@{Index=2}) -WorkerContext ([pscustomobject]@{}) -WorkerCommand Test-STSelectionWorker -OwnerId SelectionCheck
    Assert-Worker ($task.HasResult() -and -not $task.Failure()) "background start failed: $($task.Entries.Message -join ' | ')"
    $received=Receive-STBackgroundTask -TaskId $task.GetResult().TaskId -Signal $signal -Wait
    Assert-Worker ($received.HasResult() -and -not $received.Failure()) "background receive failed: $($received.Entries.Message -join ' | ')"
    $envelope=$received.GetResult().CompletionEnvelope
    Assert-Worker ($envelope.SelectionProvenance.PacketSha256 -eq $selection.PacketSha256) 'background packet mismatch'
    $null=Wait-STBackgroundTasks -OwnerId SelectionCheck -Signal $signal -RemoveAfterReceive
    $results+=[ordered]@{Case='ActualBackgroundTask';Pass=$true;Terminal=$received.GetResult().State}
    & $module { $script:STSelectionTestTag='ConduitPool' }
    $itemSignal=& (Get-Module SignalGraph) { [Signal]::Start('ConduitLocalItem') }
    Add-Type 'public class STSelectionConduitItem { public string State="Completed"; public object Signal; public void LogInformation(string message) {} }'
    $itemSignal.SetResult([pscustomobject]@{Grid=@{one=[STSelectionConduitItem]::new()}})
    $null=& $module {param($s,$item) Invoke-ConduitPool -Signal $s -Plan ([pscustomobject]@{}) -ItemSignal $item -Conductor $null} $signal $itemSignal
    $markers=@(Get-ChildItem $RunRoot -Filter '*.worker.json'|ForEach-Object {Get-Content $_.FullName -Raw|ConvertFrom-Json})
    Assert-Worker (@($markers|Where-Object Tag -eq ConduitPool).Count -gt 0) 'actual conduit pool did not start a selected worker'
    $results+=[ordered]@{Case='ActualConduitPool';Pass=$true;Workers=@($markers|Where-Object Tag -eq ConduitPool).Count}
    # Execute the exact changed pre-runtime prefix of the production parallel
    # scriptblock; its remaining adapter operations are outside loader proof.
    $source=Get-Content (Join-Path $selection.Foundation.Root 'Utilities/Adapters/Condenser/Conduit/Invoke-ProcessConduitCondenser.ps1') -Raw
    $match=[regex]::Match($source,'ForEach-Object -Parallel \{\s*(?<prefix>\$global:STSelectedWorkerContext=\$true\s*\. \$using:conduitBootstrap[\s\S]+?)\s*if \(\$using:isFailed\)')
    Assert-Worker $match.Success 'production parallel bootstrap prefix missing'
    $conduitSelection=$selection
    $conduitBootstrap=Join-Path $selection.Foundation.Root 'Bootstrap/STFoundationSelection.ps1'
    $conduitManifest=$selection.Foundation.Manifest
    $conduitKnownAssembly=& (Get-Module SignalGraph) { [Signal].Assembly.FullName }
    $prefix=$match.Groups['prefix'].Value
    [IO.File]::WriteAllText((Join-Path $RunRoot 'parallel-prefix.ps1'),$prefix)
    $parallel=[scriptblock]::Create($prefix+"`nGet-STSelectionProvenance -Selection `$verified")
    $origin=@(0|ForEach-Object -Parallel $parallel)
    Assert-Worker ($origin.Count -eq 1 -and $origin[0].PacketSha256 -eq $selection.PacketSha256) 'actual parallel bootstrap selected wrong packet'
    $results+=[ordered]@{Case='ActualParallelBootstrapPrefix';Pass=$true;Origin=$origin[0]}
    Assert-Worker ($env:PSModulePath -ceq $discoveryBeforeWorkers) 'workers mutated process discovery environment'
    $results+=[ordered]@{Case='ConcurrentWorkersEnvironmentUnchanged';Pass=$true;Discovery=$env:PSModulePath}
} catch {
    $results+=[ordered]@{Case='Failure';Pass=$false;Error=$_.Exception.Message;Stack=$_.ScriptStackTrace}
} finally {
    & $module {
        Set-Item Function:script:New-STSelectedInitialSessionState $script:STSelectionOriginalFactory
        foreach($task in @($script:STBackgroundTasks.Values)) {
            if($null -ne $task.PowerShell){$task.PowerShell.Stop();$task.PowerShell.Dispose()}
            if($null -ne $task.Runspace){$task.Runspace.Close();$task.Runspace.Dispose()}
        }
    }
}
$pass=@($results|Where-Object Pass).Count
$summary=[ordered]@{Pass=$pass;Fail=$results.Count-$pass;Total=$results.Count;Results=$results;FixtureOnly=$true}
[IO.File]::WriteAllText((Join-Path $RunRoot 'summary.json'),($summary|ConvertTo-Json -Depth 15))
$summary|ConvertTo-Json -Depth 15
if($summary.Fail){exit 1}
