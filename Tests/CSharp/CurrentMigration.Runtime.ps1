param([Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)]$Selection,[Parameter(Mandatory)][string]$Cycle)
$ErrorActionPreference='Stop'
$content=Join-Path $RunRoot content
Copy-Item -LiteralPath (Join-Path $Cycle content) -Destination $content -Recurse
foreach($name in 'modules','media','meta','resources'){$null=[IO.Directory]::CreateDirectory((Join-Path $RunRoot $name))}
$env:STTestContentRoot=$content;$env:STTestSourceRoot=Join-Path $RunRoot modules
$env:STTestMediaRoot=Join-Path $RunRoot media;$env:STTestMetaRoot=Join-Path $RunRoot meta;$env:STTestResourcesRoot=Join-Path $RunRoot resources
$definition=[pscustomobject]@{Name='Migration';Config=[pscustomobject]@{ContentRootPath=$content;SupportParallelism=$true;MaxParallelism=2};Steps=@(
 [pscustomobject]@{Name='GetAdapters';Adapter='Storage.Content';Activity='Read';Container='config';Resource='STTestApp.json';Format='Json';Path='Agents.st-test.Roles.STIntegrationTest';Key='Adapters';HydrationPlan='@'},
 [pscustomobject]@{Name='GridAdapters';Adapter='Condenser.Conduit';Activity='Graph';Path='*.#.Adapters.@.Adapters';ExitAfterAdapter=$true;Key='Adapters'},
 [pscustomobject]@{Name='Process Grid';Adapter='Condenser.Conduit';Activity='Process';ForEachPath='*.#.Adapters.@';ExitAfterAdapter=$true;ForEachInTemplate='*.#.{0}';ForEachIn='Adapters';ForEachAdapter='Condenser.Fab';ForEachActivity='Invoke';SupportParallelism=$false}
)}
try {
$outcome=& (Get-Module SovereignTrust.Foundation) {
 param($Definition)
 $global:ConsoleLoggerInstance=$null;$global:SignalTelemeter=$null
 $initialized=Initialize-STEnvironment $Definition|Select-Object -Last 1
 if($initialized.Failure() -or -not $initialized.HasResult()){throw 'MIGRATION_RUNTIME_INIT'}
 $runtime=$initialized.GetResult()
 $script:MigrationRealIteration=${function:Invoke-PlanIteration};$script:MigrationRealPool=${function:Invoke-STRunspacePool}
 $script:MigrationIterationCalls=[Collections.Generic.List[object]]::new();$script:MigrationPoolCalls=[Collections.Generic.List[object]]::new()
 function Invoke-PlanIteration {
  param($ConductionSignal,$ItemSignal,$Plan,$Iteration,[int]$IterationIndex,$IterationName,$IterationArray)
  $script:MigrationIterationCalls.Add([ordered]@{Id=$Iteration.Id;Index=$IterationIndex;Name=$IterationName;ArrayIds=@($IterationArray.Id)})
  & $script:MigrationRealIteration @PSBoundParameters|Select-Object -Last 1
 }
 function Invoke-STRunspacePool {
  param($Signal,$EnvironmentDefinition,$WorkItems,$WorkerCommand,$ThrottleLimit,$FoundationModulePath,$WorkerContext,[switch]$DebugInline,[int]$DebugWorkItemIndex)
  $observed=[ordered]@{Ids=@($WorkItems.Value.Id);Indexes=@($WorkItems.Index);ArrayIds=@($WorkerContext.IterationArray.Id);IterationName=$WorkerContext.IterationName;DebugInline=[bool]$DebugInline;WorkerCommand=$WorkerCommand;Results=@()}
  $result=& $script:MigrationRealPool @PSBoundParameters|Select-Object -Last 1
  $observed.Results=@($result.GetResult()|ForEach-Object{[ordered]@{Index=$_.Index;InitializationFailed=$_.InitializationFailed;WorkerFailed=$_.WorkerFailed;Error=$_.Error;Completed=$_.WorkerSignal.GetResult().Completed;WorkerSignalType=$_.WorkerSignal.GetType().FullName;Selection=$_.SelectionProvenance}})
  $script:MigrationPoolCalls.Add($observed)
  $result
 }
 $records=@([pscustomobject]@{Id='C';Meta=[pscustomobject]@{Rank=3};Keep=$true},[pscustomobject]@{Id='Excluded';Meta=[pscustomobject]@{Rank=[pscustomobject]@{Invalid=1}};Keep=$false},[pscustomobject]@{Id='B';Meta=[pscustomobject]@{Rank=2};Keep=$true},[pscustomobject]@{Id='B2';Meta=[pscustomobject]@{Rank=2};Keep=$true},[pscustomobject]@{Id='D';Meta=[pscustomobject]@{Rank=1.5};Keep=$true})
 function NewMigrationPlan($Parallel){[pscustomobject]@{Name='MigrationSelected';Adapter='Condenser.Plan';Activity='IteratePhase';Path='@';Steps=@();Config=[pscustomobject]@{Activity='InvokePhase';IterationArray=$records;IterationName='CurrentItem';Filter='Keep|false';OrderBy='Meta.Rank';OrderDirection='ASC';Limit=3;Threading=[pscustomobject]@{Enabled=$Parallel;Warmup=1;MaxThreads=2;ReuseItemSignalGrid=$false}}}}
 $body=@([pscustomobject]@{Name='EvaluateFraction';Adapter='Condenser.Memory';Activity='Generate';Steps=@([pscustomobject]@{Name='Compare';Adapter='Token.Dynamic';Activity='Get';Path='Dynamic.GT(1.2,1.1)';Key='MigrationComparison'})})
 $serialItem=Start-SignalWrapper -Name MigrationSerial -ReversePointer $runtime.ConductionSignal
 $null=$serialItem.CreateGraph();$null=$serialItem.SetResult($body)
 $serial=Invoke-CondenserAdapter -Slot Plan -Activity IteratePhase -Signal $runtime.ConductionSignal -Plan (NewMigrationPlan $false) -ItemSignal $serialItem|Select-Object -Last 1
 $serialCalls=@($script:MigrationIterationCalls.ToArray());$script:MigrationIterationCalls.Clear()
 if($serial.Failure()){throw ('MIGRATION_SERIAL_FAILED: '+(($serial.Entries|Where-Object Level -eq Critical|ForEach-Object Message)-join ';'))}
 $parallelItem=Start-SignalWrapper -Name MigrationParallel -ReversePointer $runtime.ConductionSignal
 $null=$parallelItem.CreateGraph();$null=$parallelItem.SetResult($body)
 $parallel=Invoke-CondenserAdapter -Slot Plan -Activity IteratePhase -Signal $runtime.ConductionSignal -Plan (NewMigrationPlan $true) -ItemSignal $parallelItem|Select-Object -Last 1
 if($parallel.Failure()){throw ('MIGRATION_PARALLEL_FAILED: '+(($parallel.Entries|Where-Object Level -eq Critical|ForEach-Object Message)-join ';'))}
 [pscustomobject]@{Serial=$serialCalls;Warmup=@($script:MigrationIterationCalls.ToArray());Pools=@($script:MigrationPoolCalls.ToArray());OriginalIds=@($records.Id);CoreOwner=$runtime.CreationOwner}
} $definition
$cases=[Collections.Generic.List[object]]::new()
function Check($Id,$Condition){$cases.Add([ordered]@{Id=$Id;Pass=[bool]$Condition})}
Check 'actual-serial-selected-fraction-filter-sort-limit' (($outcome.Serial.Id -join ',') -ceq 'D,B,B2')
Check 'actual-serial-index-and-selected-array' (($outcome.Serial.Index -join ',') -ceq '0,1,2' -and @($outcome.Serial|Where-Object{($_.ArrayIds -join ',') -cne 'D,B,B2' -or $_.Name -cne 'CurrentItem'}).Count -eq 0)
Check 'actual-warmup-selection' ($outcome.Warmup.Count -eq 1 -and $outcome.Warmup[0].Id -ceq 'D' -and $outcome.Warmup[0].Index -eq 0)
$pool=$outcome.Pools[0]
Check 'actual-real-pool-values-index-context' ($outcome.Pools.Count -eq 1 -and -not $pool.DebugInline -and ($pool.Ids -join ',') -ceq 'B,B2' -and ($pool.Indexes -join ',') -ceq '1,2' -and ($pool.ArrayIds -join ',') -ceq 'D,B,B2' -and $pool.WorkerCommand -ceq 'Invoke-PlanIterationWorker')
Check 'actual-workers-complete-native-signal' ($pool.Results.Count -eq 2 -and @($pool.Results|Where-Object{$_.InitializationFailed -or $_.WorkerFailed -or $_.Error -or -not $_.Completed -or $_.WorkerSignalType -cne 'SignalGraph.Signal'}).Count -eq 0)
Check 'actual-workers-native-selected-origin' (@($pool.Results|Where-Object{$_.Selection.SignalGraphPath -ne $Selection.SignalGraph.Assembly.Path -or $_.Selection.NativeCore.Sha256 -ne $Selection.Foundation.NativeCore.Sha256}).Count -eq 0)
Check 'caller-input-and-native-owner-preserved' (($outcome.OriginalIds -join ',') -ceq 'C,Excluded,B,B2,D' -and $outcome.CoreOwner -ceq 'NativeEnvironmentInitializer')
$fail=@($cases|Where-Object{-not $_.Pass})
$report=[ordered]@{Scope='Actual native-selected serial/warmup/real runspace iteration; test-only passthrough observers, no mocked execution';PassCount=$cases.Count-$fail.Count;FailCount=$fail.Count;SkipCount=0;Total=$cases.Count;Cases=@($cases);Observed=$outcome}
$report|ConvertTo-Json -Depth 15|Set-Content (Join-Path $RunRoot migration-runtime.json) -Encoding utf8NoBOM
if($fail.Count){throw ('MIGRATION_RUNTIME_ASSERT: '+($fail.Id -join ','))}
$report
} catch {
[ordered]@{Pass=$false;Error=$_.Exception.Message}|ConvertTo-Json|Set-Content (Join-Path $RunRoot migration-runtime-error.json)
throw
}
