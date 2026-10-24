using module SignalGraph
using module ../Src/PowerShell/SovereignTrust.Foundation.psd1
using module ../../SovereignTrust.Adapters/Src/Queue/AzureStorageQueue/PowerShell/Queue_AzureStorageQueue.psd1

$ErrorActionPreference = 'Stop'
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

$bootstrap = [Signal]::Start('FabObserve.Bootstrap') | Select-Object -Last 1
$bootstrap.SetResult([pscustomobject]@{}) | Out-Null
$started = New-Conductor -HostConductor $null -ConductionSignal $bootstrap | Select-Object -Last 1
Assert (-not $started.Failure() -and $started.HasResult()) 'Local conductor initialization failed.'
$conductor = $started.GetResult()
$control = [Signal]::Start('FabObserve.Control') | Select-Object -Last 1
$control.SetJacket($conductor.Signal) | Out-Null
$control.SetPointer($conductor.Signal.GetPointer()) | Out-Null
$run = [Signal]::Start('FabObserve.Run') | Select-Object -Last 1
$run.SetControl($control) | Out-Null
$run.SetJacket($control) | Out-Null
$run.SetPointer($conductor.Signal.GetPointer()) | Out-Null
$item = [Signal]::Start('FabObserve.Item') | Select-Object -Last 1
$item.SetPointer($conductor.Signal.GetPointer()) | Out-Null

$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).ProviderPath
$rootJacket = [pscustomobject]@{
    Kind = 'Storage'; Slot = 'ModuleRoots'
    VirtualPath = 'SovereignTrust.Adapters.Storage.EmbeddedFileSystem.ModuleRoots.Persistent.Read'
    Addresses = @($sourceRoot)
}
$root = & (Get-Module SovereignTrust.Foundation) { [Storage_EmbeddedFileSystem]::new() }
$rootConstruct = $root.Construct($rootJacket) | Select-Object -Last 1
Assert (-not $rootConstruct.Failure()) 'Local ModuleRoots construction failed.'
$rootRegistered = Register-AdapterToMappedSlot -ConductorJacketSignal $conductor.Signal -Signal $run -ConductionContext $conductor.Signal -Adapter $root | Select-Object -Last 1
Assert (-not $rootRegistered.Failure()) 'Local ModuleRoots registration failed.'

$effectGuard = [pscustomobject]@{ Denied=0; QueueRoutes=0; Modules=[System.Collections.Generic.List[string]]::new() }
& (Get-Module SovereignTrust.Foundation) {
    param($g)
    $script:FabObserveEffectGuard = $g
    $script:FabObserveMappedOriginal = (Get-Command Invoke-MappedAdapter -CommandType Function).ScriptBlock
    $script:FabObserveModuleOriginal = (Get-Command Resolve-ModuleFromAdapter -CommandType Function).ScriptBlock
    function script:Invoke-MappedAdapter {
        param($Signal,$ItemSignal,$Plan,[string]$Adapter,[string]$Activity,[string]$Name=$null)
        if ($Adapter -like 'Queue.*') { $script:FabObserveEffectGuard.QueueRoutes++ }
        if ($Adapter -like 'Queue.*' -or $Adapter -like 'Network.*' -or $Adapter -like 'Intelligence.*' -or
            $Adapter -like 'Satellite.*' -or $Adapter -like 'Storage.Secrets' -or $Adapter -eq 'Condenser.Rest') {
            $script:FabObserveEffectGuard.Denied++
            throw "Fab observation denied external adapter route: $Adapter/$Activity"
        }
        & $script:FabObserveMappedOriginal @PSBoundParameters
    }
    function script:Resolve-ModuleFromAdapter {
        param($Signal,[string]$Slot,[string]$ModuleName,[string]$RelativePath)
        if ($Slot -cne 'ModuleRoots' -or $RelativePath -notmatch '^SovereignTrust\.Adapters[\\/]Src[\\/](Queue[\\/][A-Za-z0-9_]+[\\/]PowerShell[\\/]Queue_[A-Za-z0-9_]+|Session[\\/]ST[\\/]PowerShell[\\/]Session_ST)\.psd1$') {
            $script:FabObserveEffectGuard.Denied++
            throw "Fab observation denied module path: $RelativePath"
        }
        $script:FabObserveEffectGuard.Modules.Add($RelativePath)
        & $script:FabObserveModuleOriginal @PSBoundParameters
    }
} $effectGuard
function global:Invoke-RestMethod { $effectGuard.Denied++; throw 'Fab observation denied network call.' }
function global:Invoke-WebRequest { $effectGuard.Denied++; throw 'Fab observation denied network call.' }
function global:Get-AzKeyVaultSecret { $effectGuard.Denied++; throw 'Fab observation denied secret call.' }

$sourcePath = 'SovereignTrust.Adapters.Queue.AzureStorageQueue.TestQueue.Persistent.ReadWrite'
$queueJacket = [pscustomobject]@{
    Name = 'TestQueue'; Kind = 'Queue'; Slot = 'TestQueue'; VirtualPath = $sourcePath
    Resource = 'local-nonsecret'; Addresses = @('local://unused')
}
$fab = & (Get-Module SovereignTrust.Foundation) { param($c) [FabCondenser]::Start($null, $c) } $conductor
function Register-FabSource([object]$Jacket, [string]$Mode = 'Lazy') {
    $sourceSignal = [Signal]::Start('FabObserve.SelectedRoleSource') | Select-Object -Last 1
    $sourceSignal.SetResult($Jacket) | Out-Null
    $sourceItem = [Signal]::Start('FabObserve.SelectedRoleItem') | Select-Object -Last 1
    $sourceItem.SetJacket($sourceSignal) | Out-Null
    $sourceItem.SetPointer($conductor.Signal.GetPointer()) | Out-Null
    $registrationPlan = [pscustomobject]@{ Config = [pscustomobject]@{ AdapterLoading = [pscustomobject]@{ Mode = $Mode } } }
    return $fab.Invoke('Fab', 'Invoke', $run, $registrationPlan, $sourceItem) | Select-Object -Last 1
}
$queueRegistered = Register-FabSource $queueJacket 'Eager'
if ($queueRegistered.Failure()) { $queueRegistered.GetEntries() | Select-Object -Last 5 | ForEach-Object { Write-Output ("EAGER: " + $_.Message) } }
Assert (-not $queueRegistered.Failure() -and $queueRegistered.HasResult()) 'Fab eager Queue registration failed.'
$queue = $queueRegistered.GetResult()
$queueMap = (Resolve-PathFromDictionary -Dictionary $conductor.Signal -Path '*.#.Adapters.*.#.MappedQueue' | Select-Object -Last 1).GetResult($true)
$queueGrid = $queueMap.Signal.GetPointer().Grid
$queueSlotSignal = $queueGrid['TestQueue']
$sourceIdentity = $queueSlotSignal.GetProperty('FabSourceIdentity')
Assert ($sourceIdentity.Kind -ceq 'Queue' -and $sourceIdentity.Slot -ceq 'TestQueue' -and $sourceIdentity.VirtualPath -ceq $sourcePath) 'Fab did not retain the selected role identity on the mapped slot.'
$queueSlotSignal.AddProperty('UnrelatedFixtureMeta', 'retained') | Out-Null
$queueJacket.VirtualPath = 'changed-after-registration'
Assert ($queueSlotSignal.GetProperty('FabSourceIdentity').VirtualPath -ceq $sourcePath -and $queueSlotSignal.GetProperty('UnrelatedFixtureMeta') -ceq 'retained') 'Source identity was not detached or unrelated Meta was lost.'
$queueJacket.VirtualPath = $sourcePath

$processPath = 'SovereignTrust.Adapters.Queue.AzureStorageQueue.ProcessQueue.Persistent.ReadWrite'
$processJacket = [pscustomobject]@{ Name='ProcessQueue'; Kind='Queue'; Slot='ProcessQueue'; VirtualPath=$processPath; Resource='local-nonsecret'; Addresses=@('local://unused') }
$processSource = [Signal]::Start('SelectedRole.ProcessQueue') | Select-Object -Last 1
$processSource.SetResult($processJacket) | Out-Null
$processNode = [Signal]::Start('RoleGraph.ProcessQueue') | Select-Object -Last 1
$processNode.SetJacket($processSource) | Out-Null
$processGraph = [Graph]::Start('SelectedRoleAdapters', $null, $false).GetResult()
$null = $processGraph.RegisterSignal('ProcessQueue', $processNode)
$processItem = [Signal]::Start('FabObserve.RoleGraph') | Select-Object -Last 1
$processItem.SetResult($processGraph) | Out-Null
$processPlan = [pscustomobject]@{ Name='ProcessSelectedRole'; Adapter='Condenser.Fab'; Activity='Invoke'; SupportParallelism=$false }
$processed = & (Get-Module SovereignTrust.Foundation) { param($s,$p,$i) Invoke-ProcessConduitCondenser -Signal $s -Plan $p -ItemSignal $i | Select-Object -Last 1 } $run $processPlan $processItem
if ($processed.Failure()) { $processed.GetEntries() | Select-Object -Last 5 | ForEach-Object { Write-Output ("CONDUIT: " + $_.Message) } }
Assert (-not $processed.Failure() -and $queueGrid.Contains('ProcessQueue')) 'Conduit processing did not register the selected role source.'
Assert ($queueGrid['ProcessQueue'].GetProperty('FabSourceIdentity').VirtualPath -ceq $processPath) 'Conduit source identity was not retained on its mapped slot.'
$plan = [pscustomobject]@{ Config = [pscustomobject]@{ Kind = 'Queue'; Slot = 'TestQueue'; AbsentSlot = 'NoSuchQueue' } }
$observed = $fab.Invoke('Fab', 'ObserveMappedAdapter', $run, $plan, $item) | Select-Object -Last 1
if ($observed.Failure()) { $observed.GetEntries() | ForEach-Object { Write-Output ("OBSERVE: " + $_.Message) } }
Assert (-not $observed.Failure() -and $observed.HasResult()) 'Selected Queue observation failed.'
$value = $observed.GetResult()
Assert ($value.SourceMapping -is [bool] -and $value.SourceMapping) 'Source mapping was not true Boolean.'
Assert ($value.MissingSlotAbsent -is [bool] -and $value.MissingSlotAbsent) 'Absent slot was not true Boolean.'
Assert ($value.ModuleName -ceq 'Queue_AzureStorageQueue' -and $value.ClassName -ceq 'Queue_AzureStorageQueue') 'Module or class identity mismatch.'
Assert ($value.MappedSlot -ceq 'TestQueue' -and $value.JacketVirtualPath -ceq $sourcePath) 'Mapped slot or jacket mismatch.'

$constructedJacket = $queue.Signal.GetJacket().GetResult()
$constructedJacket.VirtualPath = 'SovereignTrust.Adapters.Queue.AzureStorageQueue.TestQueue.Persistent.Read'
$mismatch = $fab.Invoke('Fab', 'ObserveMappedAdapter', $run, $plan, $item) | Select-Object -Last 1
Assert (-not $mismatch.Failure() -and $mismatch.HasResult() -and $mismatch.GetResult().SourceMapping -is [bool] -and -not $mismatch.GetResult().SourceMapping) 'Source path disagreement did not return Boolean false.'
$constructedJacket.VirtualPath = $sourcePath

$occupied = [pscustomobject]@{ Kind = 'Queue'; Slot = 'OccupiedQueue'; VirtualPath = 'SovereignTrust.Adapters.Queue.AzureStorageQueue.OccupiedQueue.Persistent.Read' }
$occupiedResult = Register-AdapterToMappedSlot -ConductorJacketSignal $conductor.Signal -Signal $run -ConductionContext $conductor.Signal -Adapter $occupied | Select-Object -Last 1
Assert (-not $occupiedResult.Failure()) 'Occupied absent-slot fixture registration failed.'
$plan.Config.AbsentSlot = 'OccupiedQueue'
$present = $fab.Invoke('Fab', 'ObserveMappedAdapter', $run, $plan, $item) | Select-Object -Last 1
Assert (-not $present.Failure() -and $present.HasResult() -and $present.GetResult().MissingSlotAbsent -is [bool] -and -not $present.GetResult().MissingSlotAbsent) 'Occupied absent slot did not return Boolean false.'
$plan.Config.AbsentSlot = 'NoSuchQueue'

$missingPlan = [pscustomobject]@{ Config = [pscustomobject]@{ Kind = 'Queue'; Slot = 'UnknownQueue'; AbsentSlot = 'NoSuchQueue' } }
$missing = $fab.Invoke('Fab', 'ObserveMappedAdapter', $run, $missingPlan, $item) | Select-Object -Last 1
Assert ($missing.Failure() -and -not $missing.HasResult()) 'Missing selected slot produced an observation.'

$lazyPath = 'SovereignTrust.Adapters.Queue.AzureStorageQueue.LazyQueue.Persistent.ReadWrite'
$lazyJacket = [Signal]::Start('FabObserve.LazyJacket') | Select-Object -Last 1
$lazyJacket.SetResult([pscustomobject]@{ Name='LazyQueue'; Kind='Queue'; Slot='LazyQueue'; VirtualPath=$lazyPath; Resource='local-nonsecret'; Addresses=@('local://unused') }) | Out-Null
$lazyRegistered = Register-FabSource ($lazyJacket.GetResult())
if ($lazyRegistered.Failure()) { $lazyRegistered.GetEntries() | Select-Object -Last 5 | ForEach-Object { Write-Output ("REGISTER: " + $_.Message) } }
Assert (-not $lazyRegistered.Failure()) 'Fab lazy Queue registration failed.'
$lazySlotSignal = $queueGrid['LazyQueue']
$lazyRegistration = $lazySlotSignal.GetResult($true)
Assert ($lazyRegistration.IsAdapterRegistration -and $lazyRegistration.State -ceq 'Registered') 'Fab lazy mode did not retain a Registered handle.'
$lazyPlan = [pscustomobject]@{ Config = [pscustomobject]@{ Kind='Queue'; Slot='LazyQueue'; AbsentSlot='NeverQueue' } }
$lazyObserved = $fab.Invoke('Fab', 'ObserveMappedAdapter', $run, $lazyPlan, $item) | Select-Object -Last 1
if ($lazyObserved.Failure()) { $lazyObserved.GetEntries() | ForEach-Object { Write-Output ("LAZY: " + $_.Message) } }
Assert (-not $lazyObserved.Failure() -and $lazyObserved.HasResult() -and $lazyObserved.GetResult().SourceMapping) 'Lazy Queue observation failed.'
$lazyInstance = $lazySlotSignal.GetResult($true)
Assert ($lazyRegistration.State -ceq 'Resolved' -and [object]::ReferenceEquals($lazyRegistration.Instance, $lazyInstance) -and $lazySlotSignal.GetProperty('FabSourceIdentity').VirtualPath -ceq $lazyPath) 'Lazy resolution did not retain cache or source identity.'
$lazyAgain = $fab.Invoke('Fab', 'ObserveMappedAdapter', $run, $lazyPlan, $item) | Select-Object -Last 1
Assert (-not $lazyAgain.Failure() -and $lazyAgain.HasResult() -and [object]::ReferenceEquals($lazySlotSignal.GetResult($true), $lazyInstance)) 'Resolved Queue cache reuse failed.'

$runId = [guid]::NewGuid().ToString('N')
$logRoot = Join-Path $sourceRoot "BDDB.Infrastructure/Documentation/Projects/Working/logs/ST-FAB-OBSERVE-EXEC-01/$runId"
$null = New-Item -ItemType Directory -Path (Join-Path $logRoot 'results') -Force
$resultPath = Join-Path $logRoot 'results/test-results-fab-observe-local.json'
$localJacket = [pscustomobject]@{
    Kind='Storage'; Slot='LocalContent'
    VirtualPath='SovereignTrust.Adapters.Storage.EmbeddedFileSystem.LocalContent.Persistent.ReadWrite'
    Addresses=@($logRoot)
}
$local = & (Get-Module SovereignTrust.Foundation) { [Storage_EmbeddedFileSystem]::new() }
$localConstruct = $local.Construct($localJacket) | Select-Object -Last 1
Assert (-not $localConstruct.Failure()) 'Local result storage construction failed.'
$localRegistered = Register-AdapterToMappedSlot -ConductorJacketSignal $conductor.Signal -Signal $run -ConductionContext $run -Adapter $local | Select-Object -Last 1
Assert (-not $localRegistered.Failure()) 'Local result storage registration failed.'

$phaseItem = [Signal]::Start('FabObserve.PhaseItem', $run) | Select-Object -Last 1
$null = $phaseItem.CreateGraph()
$phaseGraph = $phaseItem.GetPointer()
$rootPlanPath = Join-Path $sourceRoot 'BDDB.Infrastructure/integration/sovereign-trust/content/test/plans/st-test.json'
$familyPlanPath = Join-Path $sourceRoot 'BDDB.Infrastructure/integration/sovereign-trust/content/test/plans/st-test-adapter-resolution.json'
$rootPlan = @((Get-Content $rootPlanPath -Raw | ConvertFrom-Json -Depth 80) | Where-Object Name -CEQ 'STTest')[0]
$familyPlan = @((Get-Content $familyPlanPath -Raw | ConvertFrom-Json -Depth 80) | Where-Object Name -CEQ 'STTest-Adapter-Resolution')[0]
$null = $phaseGraph.RegisterResultAsSignal('STTestPlan', $rootPlan)
$null = $phaseGraph.RegisterResultAsSignal('TestFileName', 'fab-observe-local')
$phase = @($familyPlan.Phases | Where-Object Name -CEQ 'AssertTestQueue')[0]
$phaseResult = & (Get-Module SovereignTrust.Foundation) { param($s,$i,$p) Invoke-PlanPhase -ConductionSignal $s -ItemSignal $i -Phase $p | Select-Object -Last 1 } $run $phaseItem $phase
if ($phaseResult.Failure()) { $phaseResult.GetEntries() | Select-Object -Last 6 | ForEach-Object { Write-Output ("PHASE: " + $_.Message) } }
Assert (-not $phaseResult.Failure() -and $phaseResult.HasResult()) 'Selected assertion phase failed.'
Assert ($phaseGraph.Grid.Contains('TestResults')) 'Selected phase did not register TestResults.'
$record = $phaseGraph.Grid['TestResults'].GetResult().AdapterResolution
foreach ($pair in @(@('TestQueue','Mapping'),@('TestQueue','Module'),@('TestQueue','Class'),@('TestQueue','Slot'),@('TestQueue','JacketPlacement'),@('NoSuchQueue','Absent'))) {
    $leaf = $record.($pair[0]).($pair[1])
    Assert ($leaf -is [bool] -and $leaf) "Serialized assertion $($pair -join '.') was not Boolean true."
}
Assert (Test-Path $resultPath) 'Local recorder did not write its result file.'
$serialized = Get-Content $resultPath -Raw | ConvertFrom-Json -Depth 40
foreach ($pair in @(@('TestQueue','Mapping'),@('TestQueue','Module'),@('TestQueue','Class'),@('TestQueue','Slot'),@('TestQueue','JacketPlacement'),@('NoSuchQueue','Absent'))) {
    $leaf = $serialized.AdapterResolution.($pair[0]).($pair[1])
    Assert ($leaf -is [bool] -and $leaf) "Saved assertion $($pair -join '.') was not Boolean true."
}

$constructedJacket.VirtualPath = 'SovereignTrust.Adapters.Queue.AzureStorageQueue.TestQueue.Persistent.Read'
$falseItem = [Signal]::Start('FabObserve.FalseItem', $run) | Select-Object -Last 1
$null = $falseItem.CreateGraph()
$falseGraph = $falseItem.GetPointer()
$null = $falseGraph.RegisterResultAsSignal('STTestPlan', $rootPlan)
$null = $falseGraph.RegisterResultAsSignal('TestFileName', 'fab-observe-false')
$falsePath = Join-Path $logRoot 'results/test-results-fab-observe-false.json'
$falsePhase = & (Get-Module SovereignTrust.Foundation) { param($s,$i,$p) Invoke-PlanPhase -ConductionSignal $s -ItemSignal $i -Phase $p | Select-Object -Last 1 } $run $falseItem $phase
Assert (-not $falsePhase.Failure() -and $falsePhase.HasResult() -and (Test-Path $falsePath)) 'False source-mapping phase did not complete and save.'
$falseRecord = Get-Content $falsePath -Raw | ConvertFrom-Json -Depth 40
Assert ($falseRecord.AdapterResolution.TestQueue.Mapping -is [bool] -and -not $falseRecord.AdapterResolution.TestQueue.Mapping) 'Source mismatch did not serialize Boolean false.'
Assert ($falseRecord.AdapterResolution.TestQueue.Module -is [bool] -and $falseRecord.AdapterResolution.TestQueue.Module) 'Source mismatch changed unrelated module assertion.'
$constructedJacket.VirtualPath = $sourcePath

$sessionPath = 'SovereignTrust.Adapters.Session.ST.AltSession.Persistent.Read'
$sessionSource = [pscustomobject]@{ Name='AltSession'; Kind='Session'; Slot='AltSession'; VirtualPath=$sessionPath; Resource='local-nonsecret'; Addresses=@('local://unused') }
$sessionRegistered = Register-FabSource $sessionSource
Assert (-not $sessionRegistered.Failure()) 'Actual alternate Session source registration failed.'
$sessionPhase = $phase | ConvertTo-Json -Depth 80 | ConvertFrom-Json -Depth 80
$sessionPhase.Name = 'AssertAlternateSession'
$sessionPhase.Steps[0].Config.Kind = 'Session'
$sessionPhase.Steps[0].Config.Slot = 'AltSession'
$sessionPhase.Steps[0].Config.AbsentSlot = 'NoSuchSession'
$sessionItem = [Signal]::Start('FabObserve.SessionItem', $run) | Select-Object -Last 1
$null = $sessionItem.CreateGraph()
$sessionGraph = $sessionItem.GetPointer()
$null = $sessionGraph.RegisterResultAsSignal('STTestPlan', $rootPlan)
$null = $sessionGraph.RegisterResultAsSignal('TestFileName', 'fab-observe-session')
$sessionRun = & (Get-Module SovereignTrust.Foundation) { param($s,$i,$p) Invoke-PlanPhase -ConductionSignal $s -ItemSignal $i -Phase $p | Select-Object -Last 1 } $run $sessionItem $sessionPhase
if ($sessionRun.Failure()) { $sessionRun.GetEntries() | Select-Object -Last 7 | ForEach-Object { Write-Output ("SESSION: " + $_.Message) } }
Assert (-not $sessionRun.Failure() -and $sessionRun.HasResult()) 'Actual alternate Session phase failed.'
$sessionFile = Join-Path $logRoot 'results/test-results-fab-observe-session.json'
Assert (Test-Path $sessionFile) 'Alternate Session result was not saved.'
$sessionRecord = (Get-Content $sessionFile -Raw | ConvertFrom-Json -Depth 40).AdapterResolution
Assert ($sessionRecord.TestQueue.Mapping -is [bool] -and $sessionRecord.TestQueue.Mapping) 'Alternate Session source agreement was not Boolean true.'
foreach ($name in @('Module','Class','Slot','JacketPlacement')) {
    $leaf = $sessionRecord.TestQueue.$name
    Assert ($leaf -is [bool] -and -not $leaf) "Alternate Session $name did not serialize Boolean false."
}
Assert ($sessionRecord.NoSuchQueue.Absent -is [bool] -and $sessionRecord.NoSuchQueue.Absent) 'Alternate Session absent slot was not Boolean true.'

$emptySignal = [Signal]::Start('FabObserve.EmptySlot') | Select-Object -Last 1
$null = $queueMap.Signal.GetPointer().RegisterSignal('EmptyQueue', $emptySignal)
$plan.Config.AbsentSlot = 'EmptyQueue'
$emptyObserved = $fab.Invoke('Fab', 'ObserveMappedAdapter', $run, $plan, $item) | Select-Object -Last 1
Assert (-not $emptyObserved.Failure() -and $emptyObserved.HasResult() -and $emptyObserved.GetResult().MissingSlotAbsent -is [bool] -and -not $emptyObserved.GetResult().MissingSlotAbsent) 'Present empty signal was reported absent.'
$plan.Config.AbsentSlot = 'NoSuchQueue'

foreach ($presentSlot in @('OccupiedQueue','EmptyQueue')) {
    $presentPhase = $phase | ConvertTo-Json -Depth 80 | ConvertFrom-Json -Depth 80
    $presentPhase.Name = "AssertPresent$presentSlot"
    $presentPhase.Steps[0].Config.AbsentSlot = $presentSlot
    $presentItem = [Signal]::Start("FabObserve.Present$presentSlot", $run) | Select-Object -Last 1
    $null = $presentItem.CreateGraph()
    $presentGraph = $presentItem.GetPointer()
    $null = $presentGraph.RegisterResultAsSignal('STTestPlan', $rootPlan)
    $fileName = "fab-observe-present-$($presentSlot.ToLowerInvariant())"
    $null = $presentGraph.RegisterResultAsSignal('TestFileName', $fileName)
    $presentPath = Join-Path $logRoot "results/test-results-$fileName.json"
    $presentRun = & (Get-Module SovereignTrust.Foundation) { param($s,$i,$p) Invoke-PlanPhase -ConductionSignal $s -ItemSignal $i -Phase $p | Select-Object -Last 1 } $run $presentItem $presentPhase
    Assert (-not $presentRun.Failure() -and $presentRun.HasResult() -and $presentGraph.Grid.Contains('TestResults') -and (Test-Path $presentPath)) "$presentSlot selected phase did not complete and save."
    $presentObservation = $presentGraph.Grid['TestResults'].GetResult().AdapterResolution.NoSuchQueue.Absent
    Assert ($presentObservation -is [bool] -and -not $presentObservation) "$presentSlot selected phase did not observe Boolean Absent=false."
    $presentRecord = (Get-Content $presentPath -Raw | ConvertFrom-Json -Depth 40).AdapterResolution.NoSuchQueue.Absent
    Assert ($presentRecord -is [bool] -and -not $presentRecord) "$presentSlot recorder did not save JSON Boolean Absent=false."
}

$lostJacket = $queue.Signal.GetJacket()
$queue.Signal.Jacket = $null
$jacketFailure = $fab.Invoke('Fab', 'ObserveMappedAdapter', $run, $plan, $item) | Select-Object -Last 1
Assert ($jacketFailure.Failure() -and -not $jacketFailure.HasResult()) 'Missing instance jacket produced an observation.'
$queue.Signal.SetJacket($lostJacket) | Out-Null

$missingSource = [pscustomobject]@{ Name='MissingMappedQueue'; Kind='Queue'; Slot='MissingMappedQueue'; VirtualPath='SovereignTrust.Adapters.Queue.AzureStorageQueue.MissingMappedQueue.Persistent.Read'; Resource='local-nonsecret'; Addresses=@('local://unused') }
$missingRegistered = Register-FabSource $missingSource
Assert (-not $missingRegistered.Failure() -and $queueGrid.Contains('MissingMappedQueue')) 'Missing-slot fixture registration failed.'
$null = $queueMap.Signal.GetPointer().UnRegisterSignal('MissingMappedQueue')
$missingMappedPlan = [pscustomobject]@{ Config=[pscustomobject]@{ Kind='Queue'; Slot='MissingMappedQueue'; AbsentSlot='NoSuchQueue' } }
$missingMapped = $fab.Invoke('Fab', 'ObserveMappedAdapter', $run, $missingMappedPlan, $item) | Select-Object -Last 1
Assert ($missingMapped.Failure() -and -not $missingMapped.HasResult()) 'Source-present missing mapped slot produced an observation.'

$metaSource = [pscustomobject]@{ Name='NoMetaQueue'; Kind='Queue'; Slot='NoMetaQueue'; VirtualPath='SovereignTrust.Adapters.Queue.AzureStorageQueue.NoMetaQueue.Persistent.Read'; Resource='local-nonsecret'; Addresses=@('local://unused') }
$metaRegistered = Register-FabSource $metaSource
Assert (-not $metaRegistered.Failure()) 'Metadata-negative fixture registration failed.'
$queueGrid['NoMetaQueue'].Meta.PSObject.Properties.Remove('FabSourceIdentity')
$noMetaPlan = [pscustomobject]@{ Config=[pscustomobject]@{ Kind='Queue'; Slot='NoMetaQueue'; AbsentSlot='NoSuchQueue' } }
$noMeta = $fab.Invoke('Fab', 'ObserveMappedAdapter', $run, $noMetaPlan, $item) | Select-Object -Last 1
Assert ($noMeta.Failure() -and -not $noMeta.HasResult()) 'Missing source metadata produced an observation.'

$invalidSource = [pscustomobject]@{ Name='InvalidQueue'; Kind='Session'; Slot='InvalidQueue'; VirtualPath='SovereignTrust.Adapters.Queue.AzureStorageQueue.InvalidQueue.Persistent.Read' }
$invalidRegister = Register-FabSource $invalidSource
Assert ($invalidRegister.Failure() -and -not $queueGrid.Contains('InvalidQueue')) 'Invalid selected source was registered.'

$missingImport = [pscustomobject]@{ Name='MissingImport'; Kind='Queue'; Slot='MissingImport'; VirtualPath='SovereignTrust.Adapters.Queue.NoModule.MissingImport.Persistent.Read'; Resource='local-nonsecret'; Addresses=@('local://unused') }
$importRegistered = Register-FabSource $missingImport
Assert (-not $importRegistered.Failure()) 'Missing-module fixture registration failed.'
$importPlan = [pscustomobject]@{ Config=[pscustomobject]@{ Kind='Queue'; Slot='MissingImport'; AbsentSlot='NoSuchQueue' } }
$importFailure = $fab.Invoke('Fab', 'ObserveMappedAdapter', $run, $importPlan, $item) | Select-Object -Last 1
Assert ($importFailure.Failure() -and -not $importFailure.HasResult()) 'Failed lazy import produced an observation.'

$constructSource = [pscustomobject]@{ Name='ConstructFails'; Kind='Queue'; Slot='ConstructFails'; VirtualPath='SovereignTrust.Adapters.Queue.AzureStorageQueue.ConstructFails.Persistent.Read'; Resource='local-nonsecret'; Addresses=@('local://unused') }
$constructRegistered = Register-FabSource $constructSource
Assert (-not $constructRegistered.Failure()) 'Constructor-failure fixture registration failed.'
& (Get-Module SovereignTrust.Foundation) {
    $script:FabObserveResolveOriginal = (Get-Command Resolve-AdapterFromJacket -CommandType Function).ScriptBlock
    function script:Resolve-AdapterFromJacket {
        param($Signal,$ConductionContext,$Jacket)
        $source = if ($Jacket -is [Signal]) { $Jacket.GetResult() } else { $Jacket }
        if ([string]$source.Slot -ceq 'ConstructFails') {
            $failed = [Signal]::Start('FabObserve.ConstructorFailure') | Select-Object -Last 1
            $failed.LogCritical('Local constructor failure proxy.') | Out-Null
            return $failed
        }
        & $script:FabObserveResolveOriginal @PSBoundParameters
    }
}
$constructPlan = [pscustomobject]@{ Config=[pscustomobject]@{ Kind='Queue'; Slot='ConstructFails'; AbsentSlot='NoSuchQueue' } }
$constructFailure = $fab.Invoke('Fab', 'ObserveMappedAdapter', $run, $constructPlan, $item) | Select-Object -Last 1
Assert ($constructFailure.Failure() -and -not $constructFailure.HasResult() -and $queueGrid['ConstructFails'].GetResult($true).State -ceq 'Failed') 'Failed lazy construction proxy produced an observation or lost failure state.'

& (Get-Module SovereignTrust.Foundation) {
    $script:FabObserveModuleTableMode = 'Missing'
    function script:Get-Module {
        param([string]$Name)
        if ($Name -ceq 'Queue_AzureStorageQueue' -and $script:FabObserveModuleTableMode -ceq 'Missing') { return }
        $actual = @(Microsoft.PowerShell.Core\Get-Module -Name $Name)
        if ($Name -ceq 'Queue_AzureStorageQueue' -and $script:FabObserveModuleTableMode -ceq 'Duplicate') {
            return @($actual[0], $actual[0])
        }
        return $actual
    }
}
$missingModuleIdentity = $fab.Invoke('Fab', 'ObserveMappedAdapter', $run, $plan, $item) | Select-Object -Last 1
Assert ($missingModuleIdentity.Failure() -and -not $missingModuleIdentity.HasResult()) 'Missing loaded module identity produced an observation.'
& (Get-Module SovereignTrust.Foundation) { $script:FabObserveModuleTableMode = 'Duplicate' }
$ambiguousModuleIdentity = $fab.Invoke('Fab', 'ObserveMappedAdapter', $run, $plan, $item) | Select-Object -Last 1
Assert ($ambiguousModuleIdentity.Failure() -and -not $ambiguousModuleIdentity.HasResult()) 'Ambiguous loaded module identity produced an observation.'
& (Get-Module SovereignTrust.Foundation) { $script:FabObserveModuleTableMode = 'Actual' }

$savedGraph = $queueMap.Signal.GetPointer()
$queueMap.Signal.SetPointer($null) | Out-Null
$graphFailure = $fab.Invoke('Fab', 'ObserveMappedAdapter', $run, $plan, $item) | Select-Object -Last 1
Assert ($graphFailure.Failure() -and -not $graphFailure.HasResult()) 'Unavailable mapped graph produced an observation.'
$queueMap.Signal.SetPointer($savedGraph) | Out-Null
Assert (& (Get-Module SovereignTrust.Foundation) { $null -ne [MappedCondenserAdapter].GetMethod('InvokeOld') }) 'Distinct MappedCondenserAdapter.InvokeOld was removed.'
Assert ($effectGuard.Denied -eq 0 -and $effectGuard.QueueRoutes -eq 0) 'Provider, secret, network or Queue invocation guard was reached.'
$receipt = [ordered]@{
    RunId = $runId
    Source = 'Fab.Invoke and Conduit.Process selected role item'
    Positive = 'Six saved Queue Boolean true leaves'
    FalseRecords = @('Queue.Mapping','Session.Module','Session.Class','Session.Slot','Session.JacketPlacement')
    FailedWithoutObservation = @('MissingMappedSlot','MissingMeta','InvalidSource','MissingImport','ConstructorFailureProxy','MissingModuleIdentityProxy','AmbiguousModuleIdentityProxy','MissingInstanceJacket','UnavailableGraph')
    EmptyAbsentSlotReportedPresent = $true
    PopulatedAndEmptyAbsentSlotsSavedFalse = @('OccupiedQueue','EmptyQueue')
    LazyResolvedAndReusedSameInstance = $true
    UnrelatedMetaPreserved = $true
    DeniedEffectCalls = $effectGuard.Denied
    QueueRoutes = $effectGuard.QueueRoutes
    LocalModules = @($effectGuard.Modules)
}
$receiptPath = Join-Path $logRoot 'receipt.json'
[IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 8))
Write-Output "PASS: selected source retention, six true Booleans, false records, failure branches, guards; run=$runId"
