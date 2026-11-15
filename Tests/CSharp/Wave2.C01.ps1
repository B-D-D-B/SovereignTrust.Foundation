param([Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)]$Selection,[Parameter(Mandatory)][string]$Cycle)
$ErrorActionPreference='Stop'
if($Selection.SignalGraph.Backend -eq 'Native'){$env:ST_NATIVE_ABI_TRACE=Join-Path $RunRoot 'native-abi-failures.jsonl'}
$spec=Get-Content (Join-Path $Cycle 'spec.json') -Raw|ConvertFrom-Json -Depth 80
$app=Get-Content (Join-Path $Cycle 'content/config/STTestApp.json') -Raw|ConvertFrom-Json -Depth 80
$role=$app.Agents[0].Roles[0]
if($spec.Schema -cne 'ST.C01/1' -or $role.ExpectedResults.Count -ne 4 -or $role.Adapters.Count -ne 2 -or @($role.Adapters|Where-Object{$_.VirtualPath -notlike 'SovereignTrust.Adapters.Storage.EmbeddedFileSystem.*'}).Count){throw 'C01_PREFLIGHT: exact local-only role required'}
$content=[IO.Path]::GetFullPath((Join-Path $RunRoot 'content'))
if(Test-Path $content){throw 'C01_RUN_ROOT: content already exists'}
Copy-Item -LiteralPath (Join-Path $Cycle 'content') -Destination $content -Recurse
foreach($dir in 'modules','media','meta','resources'){$null=[IO.Directory]::CreateDirectory((Join-Path $RunRoot $dir))}
$env:STTestContentRoot=$content;$env:STTestSourceRoot=Join-Path $RunRoot 'modules'
$env:STTestMediaRoot=Join-Path $RunRoot 'media';$env:STTestMetaRoot=Join-Path $RunRoot 'meta';$env:STTestResourcesRoot=Join-Path $RunRoot 'resources'
$definition=[pscustomobject]@{Name='C01';Config=[pscustomobject]@{ContentRootPath=$content;SupportParallelism=$false};Steps=@(
    [pscustomobject]@{Name='GetAdapters';Adapter='Storage.Content';Activity='Read';Container='config';Resource='STTestApp.json';Format='Json';Path='Agents.st-test.Roles.STIntegrationTest';Key='Adapters';HydrationPlan='@'},
    [pscustomobject]@{Name='GridAdapters';Adapter='Condenser.Conduit';Activity='Graph';Path='*.#.Adapters.@.Adapters';ExitAfterAdapter=$true;Key='Adapters'},
    [pscustomobject]@{Name='Process Grid';Adapter='Condenser.Conduit';Activity='Process';ForEachPath='*.#.Adapters.@';ExitAfterAdapter=$true;ForEachInTemplate='*.#.{0}';ForEachIn='Adapters';ForEachAdapter='Condenser.Fab';ForEachActivity='Invoke';SupportParallelism=$false}
)}
$report=[ordered]@{Scope='Actual C01 PS business logic';Backend='PowerShell';ExpectedResults=$role.ExpectedResults;ExpectedCount=4;ExecutedCount=0;UnstartedCount=4;Pass=$false;Stage='Initialize';SignalEntries=@();InitializationSteps=$definition.Steps.Name;AppSha256=(Get-FileHash (Join-Path $content 'config/STTestApp.json')).Hash;SpecSha256=(Get-FileHash (Join-Path $Cycle 'spec.json')).Hash;OriginalFoundation=$Selection.Foundation.Manifest;SignalGraph=$Selection.SignalGraph.Manifest}
try {
    $outcome=& (Get-Module SovereignTrust.Foundation) {
        param($Definition,$RolePlan,$Native)
        function Failed($Value){if($Native){$Value.Failure()}else{$Value.Failure()}}
        function NewC01Signal($Name,$ReversePointer){if($Native){$t=[type]::GetType('SignalGraph.Signal, SignalGraph',$true);$t::Start($Name,$ReversePointer)}else{[Signal]::Start($Name,$ReversePointer)}}
        $global:ConsoleLoggerInstance=$null;$global:SignalTelemeter=$null
        $parent=NewC01Signal 'C01.Initialize.Parent' $null|Select-Object -Last 1
        $wrapperFailurePreserved=$false
        if($Native){
            $invalid=Initialize-STEnvironment -Environment @{1='non-string-json-key'} -ParentSignal $parent|Select-Object -Last 1
            $wrapperFailurePreserved=$null -ne $invalid -and $invalid.Failure() -and [object]::ReferenceEquals($invalid.ReversePointer,$parent) -and @($invalid.Entries|Where-Object{[string]$_.Level -ceq 'Critical'}).Count -gt 0
            if(-not $wrapperFailurePreserved){throw 'C01_INITIALIZER_ERROR_CONTRACT: invalid pre-native clone must return Critical Signal retaining parent'}
        }
        $init=Initialize-STEnvironment -Environment $Definition -ParentSignal $parent|Select-Object -Last 1
        $wrapperParentPreserved=if($Native){[object]::ReferenceEquals($init.ReversePointer,$parent)}else{$true}
        if(-not $wrapperParentPreserved){throw 'C01_INITIALIZER_PARENT_CONTRACT: operation parent identity changed'}
        if($null -eq $init -or (Failed $init) -or -not $init.HasResult()){
            return [pscustomobject]@{Pass=$false;Stage='Initialize';Entries=@($init.Entries|ForEach-Object{[ordered]@{Message=$_.Message;Level=[string]$_.Level}})}
        }
        $runtime=$init.GetResult();$item=NewC01Signal 'C01' $runtime.ConductionSignal|Select-Object -Last 1
        $null=$item.CreateGraph();$null=$item.GetPointer().RegisterResultAsSignal('SelectedTestPlan',$RolePlan)
        $invocation=[pscustomobject]@{Name='C01.Invoke';Steps=@([pscustomobject]@{Name='C01.Invoke';Adapter='Condenser.Plan';Activity='InvokePhase';Path='*.#.SelectedTestPlan.@.Phases.FullSuite.Steps';ExitAfterAdapter=$true})}
        $result=Invoke-PlanPhase -ConductionSignal $runtime.ConductionSignal -ItemSignal $item -Phase $invocation|Select-Object -Last 1
        $values=[ordered]@{}
        foreach($entry in @{RunId='*.#.TestRunId.@';TestFileName='*.#.TestFileName.@';TestResults='*.#.TestResults.@';TestRecordEvents='*.#.TestRecordEvents.@'}.GetEnumerator()){
            $observed=Resolve-PathFromDictionary -Dictionary $item -Path $entry.Value|Select-Object -Last 1
            $values[$entry.Key]=if($observed.HasResult()){$observed.GetResult()}else{$null}
        }
        # Named retained values only; never traverse the cyclic runtime graph.
        $readValues=@();$providers=@();$rawRead=$null;$rawReadType=$null
        $read=Resolve-PathFromDictionary -Dictionary $item -Path '*.#.WrittenTestFile_LocalContent.@' -SignalLevel Warning|Select-Object -Last 1
        if($read.HasResult()){$rawRead=$read.GetResult($true);$rawReadType=$rawRead.GetType().AssemblyQualifiedName;$readValues=@($rawRead)}
        $mappedResult=Resolve-PathFromDictionary -Dictionary $runtime.Conductor -Path '$.*.#.Adapters.*.#.MappedStorage.@'|Select-Object -Last 1
        $mapped=$mappedResult.GetResult($true)
        if($null -ne $mapped){
            $slot=$mapped.Signal.GetPointer().Grid['LocalContent']
            if($null -ne $slot){$registered=$slot.GetResult($true);$provider=if($registered.IsAdapterRegistration){$registered.Instance}else{$registered}
                if($null -ne $provider){$providers=@([ordered]@{Type=$provider.GetType().AssemblyQualifiedName;SignalType=$provider.Signal.GetType().AssemblyQualifiedName;InstanceIdentity=[Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($provider)})}
            }
        }
        $probe=NewC01Signal 'C01.live-identity' $null|Select-Object -Last 1;$g=$runtime.ConductionSignal.GetPointer();$null=$probe.SetPointer($g);$null=$probe.SetJacket($probe);$probe.SetControl($probe);$null=$g.RegisterSignal('C01.LiveIdentity',$probe)
        $identity=[object]::ReferenceEquals($g.Grid['c01.liveidentity'],$probe) -and [object]::ReferenceEquals($probe.GetPointer(),$g) -and [object]::ReferenceEquals($probe.GetJacket(),$probe) -and [object]::ReferenceEquals($probe.GetControl(),$probe)
        $coreEvidence=$null
        if($runtime.Conductor.PSObject.Properties['NativeRuntime'] -and $null -ne $runtime.Conductor.NativeRuntime){
            $core=$runtime.Conductor.NativeRuntime
            $observePlan=[pscustomobject]@{Config=[pscustomobject]@{Kind='Storage';Slot='LocalContent';AbsentSlot='Wave2AbsentSlot'}}
            $observedFab=Invoke-CondenserAdapter -Slot Fab -Activity ObserveMappedAdapter -Signal $runtime.ConductionSignal -Plan $observePlan -ItemSignal $item|Select-Object -Last 1
            if($null -eq $observedFab -or (Failed $observedFab) -or -not $observedFab.HasResult()){throw 'C01_NATIVE_FAB_OBSERVATION: actual registered leaf observation failed'}
            $coreEvidence=[ordered]@{Type=$core.GetType().AssemblyQualifiedName;AssemblyPath=$core.GetType().Assembly.Location;AssemblySha256=(Get-FileHash $core.GetType().Assembly.Location).Hash;DispatchCount=$core.DispatchCount;RegistrySlots=@($core.Slots);SharedSignal=[object]::ReferenceEquals($core.Signal,$runtime.Conductor.Signal);SharedMemory=[object]::ReferenceEquals($core.Memory,$runtime.Conductor.Signal.GetPointer());StorageState=[string]$core.GetRegistration('Storage.LocalContent').State;CondenserState=[string]$core.GetRegistration('Condenser.MemoryCondenser').State;CreationOwner=$runtime.CreationOwner;RuntimeType=$runtime.GetType().FullName;NativeFamilies=$core.NativeFamiliesInitialized;NativeRegistrations=$core.NativeRegistrationCount;NativeConstructions=$core.NativeConstructionCount;FabRegistrations=$core.FabRegistrationCount;NativeFabType=$core.GetFamily('Condenser').Graph.Grid['FabCondenser'].Result.GetType().FullName}
            $coreEvidence.FabObservation=$observedFab.GetResult()
            $coreEvidence.FabObservations=$core.FabObservationCount
            $coreEvidence.WrapperParentPreserved=$wrapperParentPreserved
            $coreEvidence.WrapperCloneFailureAsSignal=$wrapperFailurePreserved
        }
        [pscustomobject]@{Pass=(-not (Failed $result));Stage='Plan';Values=$values;CompleteReadValues=$readValues;RawRead=$rawRead;RawReadType=$rawReadType;Providers=$providers;LiveGraphIdentity=$identity;NativeCore=$coreEvidence;ItemKeys=@($item.GetPointer().GetKeys());Entries=@($result.Entries|ForEach-Object{[ordered]@{Message=$_.Message;Level=[string]$_.Level}})}
    } $definition $role.Plan ($Selection.SignalGraph.Backend -eq 'Native')
    $report.Stage=$outcome.Stage;$report.SignalEntries=$outcome.Entries
    if($outcome.Stage -eq 'Plan'){$report.Values=$outcome.Values;$report.ProductPlanCompleted=[bool]$outcome.Pass;$report.ItemKeys=$outcome.ItemKeys;$report.ObservedRead=$outcome.CompleteReadValues;$report.ObservedProviders=$outcome.Providers;$report.ObservedIdentity=$outcome.LiveGraphIdentity;$report.TestResultsRuntimeType=if($null -eq $outcome.Values.TestResults){'<null>'}else{$outcome.Values.TestResults.GetType().FullName}}
    if(-not $outcome.Pass){throw "C01_$($outcome.Stage.ToUpperInvariant()): actual source path failed"}
    $assertionFailures=[Collections.Generic.List[string]]::new()
    function Require($Condition,$Id){if(-not $Condition){$assertionFailures.Add($Id)}}
    $expectedIds=@($role.ExpectedResults|ForEach-Object{"$($_.Group)/$($_.Name)"}|Sort-Object)
    $runId=[string]$outcome.Values.RunId;Require (-not [string]::IsNullOrWhiteSpace($runId)) 'current-run-id'
    $leaves=[Collections.Generic.List[object]]::new()
    function Entries($Value){if($Value -is[Collections.IDictionary]){foreach($key in $Value.Keys){[pscustomobject]@{Name=[string]$key;Value=$Value[$key]}}}else{$Value.PSObject.Properties|ForEach-Object{[pscustomobject]@{Name=$_.Name;Value=$_.Value}}}}
    function Walk($Value,$Prefix){if($Value -is [pscustomobject] -or $Value -is[Collections.IDictionary]){foreach($prop in @(Entries $Value)){if($prop.Name -ceq 'Timestamp' -and -not $Prefix){continue};Walk $prop.Value $(if($Prefix){$Prefix+'/'+$prop.Name}else{$prop.Name})}}else{$leaves.Add([ordered]@{Path=$Prefix;Value=$Value})}}
    Walk $outcome.Values.TestResults ''
    $report.ExecutedCount=$leaves.Count;$report.UnstartedCount=[Math]::Max(0,4-$leaves.Count)
    $actualIds=@($leaves|ForEach-Object{$p=$_.Path.Split('/');$p[0]+'/'+($p[1..($p.Length-1)] -join '.')}|Sort-Object)
    Require ($actualIds.Count -eq4 -and ($actualIds -join '|') -ceq ($expectedIds -join '|') -and @($leaves|Where-Object{$_.Value -isnot [bool] -or $_.Value -ne $true}).Count -eq0) 'exact-four-native-true-leaves'
    $events=@(Entries $outcome.Values.TestRecordEvents)
    Require ($events.Count -eq4 -and @($events.Value.EventId|Sort-Object -Unique).Count -eq4) 'unique-four-event-ids'
    foreach($e in $events){Require ($e.Name -ceq $e.Value.EventId -and $e.Value.RunId -ceq $runId -and $e.Value.Value -is[bool] -and $e.Value.Value -eq $true) 'current-correlated-native-true-event'}
    Require ((@($events|ForEach-Object{"$($_.Value.Group)/$($_.Value.Name)"}|Sort-Object) -join '|') -ceq ($expectedIds -join '|')) 'exact-event-inventory'
    $verboseFile=@(Get-ChildItem (Join-Path $content 'results') -File -Filter '*-STTest-Adapters-Storage-verbose.json');Require ($verboseFile.Count -eq1) 'one-current-verbose-report'
    $verbose=(Get-Content $verboseFile[0].FullName -Raw|ConvertFrom-Json -Depth 40).StorageAdapter.LocalContent
    Require (@($verbose.PSObject.Properties).Count -eq4) 'exact-verbose-inventory'
    $writePath=$verbose.WriteContent.Value;Require ($writePath -is[string] -and $writePath.StartsWith($content+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -and -not (Test-Path -LiteralPath $writePath)) 'real-write-path-deleted-inside-root'
    Require ($verbose.DeleteContent.Value -is[bool] -and $verbose.DeleteContent.Value -eq $true -and $verbose.ExistsContent.Value -is[bool] -and $verbose.ExistsContent.Value -eq $false) 'native-delete-true-exists-false'
    $expectedRead=(Get-Content (Join-Path $Cycle 'content/fixtures/storage/content-cases.json') -Raw|ConvertFrom-Json -Depth 40)[0].Cases.SharedJson.Expected
    $report.ItemKeys=$outcome.ItemKeys
    Require ($outcome.CompleteReadValues.Count -gt0) 'actual-full-read-observation-present'
    Require ($outcome.RawRead -isnot [array] -and (ConvertTo-Json -InputObject $outcome.RawRead -Depth 40 -Compress) -ceq (ConvertTo-Json -InputObject $expectedRead -Depth 40 -Compress)) 'complete-shared-json-value-and-object-shape'
    Require ($outcome.Providers.Count -gt0 -and $outcome.LiveGraphIdentity) 'actual-provider-and-live-identity'
    if($Selection.Foundation.NativeCore){Require ($null -ne $outcome.NativeCore -and $outcome.NativeCore.SharedSignal -and $outcome.NativeCore.SharedMemory -and $outcome.NativeCore.DispatchCount -gt0 -and $outcome.NativeCore.StorageState -ceq 'Resolved' -and $outcome.NativeCore.CondenserState -ceq 'Resolved' -and $outcome.NativeCore.AssemblyPath -eq $Selection.Foundation.NativeCore.Path -and $outcome.NativeCore.AssemblySha256 -ceq $Selection.Foundation.NativeCore.Sha256) 'actual-native-core-registry-dispatch-and-shared-context'}
    if($Selection.Foundation.NativeCore){Require ($outcome.NativeCore.CreationOwner -ceq 'NativeEnvironmentInitializer' -and $outcome.NativeCore.RuntimeType -ceq 'SovereignTrust.Foundation.Utilities.Conduction.EnvironmentRuntime' -and $outcome.NativeCore.NativeFamilies -and $outcome.NativeCore.NativeRegistrations -ge37 -and $outcome.NativeCore.NativeConstructions -ge23 -and $outcome.NativeCore.FabRegistrations -ge3 -and $outcome.NativeCore.NativeFabType -ceq 'SovereignTrust.Foundation.Classes.Adapters.Condenser.FabCondenser') 'actual-native-environment-conductor-fab-ownership'}
    if($Selection.Foundation.NativeCore){$observed=$outcome.NativeCore.FabObservation;Require ($observed.SourceMapping -and $observed.MissingSlotAbsent -and $observed.ModuleName -ceq 'SovereignTrust.Foundation' -and $observed.ClassName -ceq 'Storage_EmbeddedFileSystem' -and $observed.MappedSlot -ceq 'LocalContent' -and $observed.JacketVirtualPath -ceq 'SovereignTrust.Adapters.Storage.EmbeddedFileSystem.LocalContent.Persistent.Read' -and $observed.RegistrationState -ceq 'Resolved' -and $outcome.NativeCore.FabObservations -eq 1) 'actual-native-fab-observation-selected-jacket-type-module'}
    if($Selection.Foundation.NativeCore){Require ($outcome.NativeCore.WrapperParentPreserved -and $outcome.NativeCore.WrapperCloneFailureAsSignal) 'actual-exported-initializer-parent-and-pre-native-exception-signal'}
    $report.AssertionFailures=@($assertionFailures)
    if($assertionFailures.Count){$report.FailCount=$assertionFailures.Count;throw "C01_ASSERT: $($assertionFailures -join ', ')"}
    $report.ExecutedCount=4;$report.UnstartedCount=0;$report.PassCount=4;$report.FailCount=0;$report.SkipCount=0;$report.Pass=$true
    $report.Operations=[ordered]@{WritePath=$writePath;Read=$outcome.RawRead;ReadType=$outcome.RawReadType;ExpectedRead=$expectedRead;Delete=$verbose.DeleteContent.Value;Exists=$verbose.ExistsContent.Value}
    $report.Providers=$outcome.Providers;$report.LiveGraphIdentity=$outcome.LiveGraphIdentity;$report.EventCount=$events.Count
    $report.NativeCore=$outcome.NativeCore
    $report|ConvertTo-Json -Depth 40|Set-Content (Join-Path $RunRoot 'c01-result.json') -Encoding utf8NoBOM
    [pscustomobject]$report
}catch{
    $report.Error=$_.Exception.Message
    $report|ConvertTo-Json -Depth 30|Set-Content (Join-Path $RunRoot 'c01-result.json') -Encoding utf8NoBOM
    throw
}
