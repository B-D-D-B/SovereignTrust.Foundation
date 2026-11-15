param([Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)]$Selection,[Parameter(Mandatory)][string]$Cycle)
$ErrorActionPreference='Stop'
$app=Get-Content (Join-Path $Cycle content/config/STTestApp.json) -Raw|ConvertFrom-Json -Depth 80
$content=Join-Path $RunRoot content
if(Test-Path $content){throw 'StageA content root must be new'}
Copy-Item (Join-Path $Cycle content) $content -Recurse
foreach($dir in 'modules','media','meta','resources'){$null=[IO.Directory]::CreateDirectory((Join-Path $RunRoot $dir))}
$env:STTestContentRoot=$content;$env:STTestSourceRoot=Join-Path $RunRoot modules
$env:STTestMediaRoot=Join-Path $RunRoot media;$env:STTestMetaRoot=Join-Path $RunRoot meta;$env:STTestResourcesRoot=Join-Path $RunRoot resources
$definition=[pscustomobject]@{Name='C01';Config=[pscustomobject]@{ContentRootPath=$content;SupportParallelism=$false};Steps=@(
    [pscustomobject]@{Name='GetAdapters';Adapter='Storage.Content';Activity='Read';Container='config';Resource='STTestApp.json';Format='Json';Path='Agents.st-test.Roles.STIntegrationTest';Key='Adapters';HydrationPlan='@'},
    [pscustomobject]@{Name='GridAdapters';Adapter='Condenser.Conduit';Activity='Graph';Path='*.#.Adapters.@.Adapters';ExitAfterAdapter=$true;Key='Adapters'},
    [pscustomobject]@{Name='Process Grid';Adapter='Condenser.Conduit';Activity='Process';ForEachPath='*.#.Adapters.@';ExitAfterAdapter=$true;ForEachInTemplate='*.#.{0}';ForEachIn='Adapters';ForEachAdapter='Condenser.Fab';ForEachActivity='Invoke';SupportParallelism=$false}
)}
$phaseFile=Join-Path $Cycle unsupported-activity.json
$phase=Get-Content $phaseFile -Raw|ConvertFrom-Json -Depth 20
$native=$Selection.SignalGraph.Backend -eq 'Native'
$result=& (Get-Module SovereignTrust.Foundation) {
    param($Definition,$Phase,$Native,$PhaseFile,$FoundationRoot)
    $global:ConsoleLoggerInstance=$null;$global:SignalTelemeter=$null
    $init=Initialize-STEnvironment $Definition|Select-Object -Last 1
    $initFailed=if($Native){$init.Failure()}else{$init.Failure()}
    if($initFailed -or -not $init.HasResult()){throw 'STAGEA_NEGATIVE: real local initialization failed'}
    $runtime=$init.GetResult()
    $item=Start-SignalWrapper -Name StageAFailure -ReversePointer $runtime.ConductionSignal
    $null=$item.CreateGraph()
    $condenserSource=Join-Path $FoundationRoot 'Wrappers/Adapters/Invoke-CondenserAdapter.ps1'
    $tokenSource=Join-Path $FoundationRoot 'Utilities/Adapters/Token/Invoke-MappedTokenAdapter.ps1'
    Start-STExecutionTrace -Context @{RunId='wave2';CaseId='actual-local-failure';CorrelationId='stageA';Sources=@{
        Plan=@{Path=$PhaseFile;Sha256=(Get-FileHash $PhaseFile).Hash;Location='Steps'}
        Condenser=@{Path=$condenserSource;Sha256=(Get-FileHash $condenserSource).Hash;Location='Invoke-CondenserAdapter'}
        Token=@{Path=$tokenSource;Sha256=(Get-FileHash $tokenSource).Hash;Location='Invoke-MappedTokenAdapter'}
    }}
    try{$failed=Invoke-PlanPhase -ConductionSignal $runtime.ConductionSignal -ItemSignal $item -Phase $Phase|Select-Object -Last 1;$trace=Get-STExecutionTrace}finally{Stop-STExecutionTrace}
    $isFailed=if($Native){$failed.Failure()}else{$failed.Failure()}
    [pscustomobject]@{Failed=$isFailed;Entries=@($failed.Entries|ForEach-Object{[ordered]@{Level=[string]$_.Level;Message=$_.Message}});Trace=$trace;SignalType=$failed.GetType().AssemblyQualifiedName}
} $definition $phase $native $phaseFile $Selection.Foundation.Root
$cases=[Collections.Generic.List[object]]::new()
function Check($Id,$Condition){$cases.Add([ordered]@{Id=$Id;Pass=[bool]$Condition})}
Check 'actual-mapped-storage-unsupported-critical' ($result.Failed -and @($result.Entries|Where-Object{$_.Level -ceq 'Critical' -and $_.Message -ceq "Unsupported MappedStorageAdapter activity: 'Wave2Unsupported'."}).Count -eq 1)
Check 'later-step-never-entered' ($result.Trace.Complete -and @($result.Trace.Rows|Where-Object{$_.StepName -eq 'LaterSentinel' -or $_.BoundaryName -eq 'LaterSentinel'}).Count -eq 0)
Check 'later-storage-write-absent' (-not (Test-Path (Join-Path $content sentinel/must-not-exist.json)))
$snapshot=& (Get-Module SovereignTrust.Foundation) {
    $source=Start-SignalWrapper -Name SnapshotSource
    $null=$source.CreateGraph()
    $value=[pscustomobject]@{Name='LaunchValue';Nested=[pscustomobject]@{Count=1}}
    $null=$source.GetPointer().RegisterResultAsSignal('SharedValue',$value)
    $export=Export-STSignalGraphSnapshot -ItemSignal $source|Select-Object -Last 1
    $json=[string]$export.GetResult()
    $value.Name='ChangedAfterExport';$value.Nested.Count=2
    [pscustomobject]@{Json=$json;OriginalValue=$value}
}
$worker=New-STSelectedRunspace $Selection
$ps=[powershell]::Create()
try{
    $ps.Runspace=$worker
    $null=$ps.AddScript({param($json)
        & (Get-Module SovereignTrust.Foundation) {
            param($json)
            $conduction=Start-SignalWrapper -Name SnapshotWorker
            $null=$conduction.CreateGraph()
            $null=$conduction.GetPointer().RegisterResultAsSignal('EnvironmentDetails','WorkerEnvironment')
            $import=Import-STSignalGraphSnapshot -SnapshotJson $json -ConductionSignal $conduction|Select-Object -Last 1
            $item=$import.GetResult();$value=$item.GetPointer().Grid['SharedValue'].GetResult()
            $record=ConvertFrom-STSignalRecord ([pscustomobject]@{Name='Record';Meta=@{};Entries=@([pscustomobject]@{Level='Warning';Message='Worker record';Tags=@()});HasResult=$true;Result=[pscustomobject]@{Value=$false}})
            [pscustomobject]@{ValueName=$value.Name;ValueCount=$value.Nested.Count;Environment=$item.GetPointer().Grid['EnvironmentDetails'].Result;SignalType=$item.GetType().AssemblyQualifiedName;GraphType=$item.GetPointer().GetType().AssemblyQualifiedName;RecordType=$record.GetType().AssemblyQualifiedName;RecordValue=$record.Result.Value;RecordLevel=[string]$record.Level;SignalAssembly=$item.GetType().Assembly.Location}
        } $json
    }.ToString()).AddArgument($snapshot.Json)
    $workerResults=@($ps.Invoke())
    if($ps.HadErrors -or $workerResults.Count -ne 1){throw "STAGEA_WORKER: $($ps.Streams.Error|Out-String)"}
    $workerResult=$workerResults[0]
    $workerProvenance=$worker.STSelectionProvenance
}finally{$ps.Dispose();$worker.Close();$worker.Dispose()}
Check 'worker-record-snapshot-family' ($workerResult.SignalType -ceq $workerProvenance.SignalType -and $workerResult.RecordType -ceq $workerProvenance.SignalType)
Check 'worker-snapshot-clone-values' ($workerResult.ValueName -ceq 'LaunchValue' -and $workerResult.ValueCount -eq 1 -and $snapshot.OriginalValue.Name -ceq 'ChangedAfterExport')
Check 'worker-environment-preserved' ($workerResult.Environment -ceq 'WorkerEnvironment')
Check 'worker-feedback-record-native-false' ($workerResult.RecordValue -is [bool] -and $workerResult.RecordValue -eq $false -and $workerResult.RecordLevel -ceq 'Warning')
$report=[ordered]@{Backend=if($native){'PowerShell Foundation/native SG'}else{'Original PowerShell'};PassCount=@($cases|Where-Object Pass).Count;FailCount=@($cases|Where-Object{-not $_.Pass}).Count;SkipCount=0;Total=$cases.Count;Cases=@($cases);Negative=$result;Worker=$workerResult;WorkerProvenance=$workerProvenance;WorkerDisposed=$true;WorkerBoundary='Existing record JSON clone protocol; no cross-worker reference identity claim';PhaseSha256=(Get-FileHash $phaseFile).Hash;AppSha256=(Get-FileHash (Join-Path $Cycle content/config/STTestApp.json)).Hash}
$report|ConvertTo-Json -Depth 35|Set-Content (Join-Path $RunRoot stageA-result.json) -Encoding utf8NoBOM
if($report.FailCount){throw "STAGEA_ASSERT: $(@($cases|Where-Object{-not $_.Pass}|ForEach-Object Id) -join ',')"}
[pscustomobject]$report
