using module ../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

$ErrorActionPreference = 'Stop'
$siblingModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../SignalGraph/Src/PowerShell')).ProviderPath
$env:PSModulePath = $siblingModuleRoot + [IO.Path]::PathSeparator + $env:PSModulePath
Import-Module (Join-Path $PSScriptRoot '../Src/PowerShell/SovereignTrust.Foundation.psd1') -Force
$script:assertions = 0
function Assert-True([bool]$condition, [string]$message) {
    $script:assertions++
    if (-not $condition) { throw $message }
}
function New-Item([object]$value) {
    $graph = ([Graph]::Start('SignalCondenser.Tests', $null, $false) | Select-Object -Last 1).GetResult()
    $item = [Signal]::Start('Item') | Select-Object -Last 1
    $null = $item.SetPointer($graph)
    $null = $graph.RegisterResultAsSignal('Subject', $value)
    return $item
}
function Invoke-Leaf([string]$activity, [object]$config, [Signal]$item) {
    $plan = [pscustomobject]@{ Name = 'SignalStep'; Config = $config }
    return $script:condenser.Invoke('Signal', $activity, ([Signal]::Start('Conduction') | Select-Object -Last 1), $plan, $item)
}
function Assert-Failure([Signal]$result, [string]$case) {
    Assert-True ($result.Failure() -and -not $result.HasResult()) "$case must fail without Result."
    Assert-True (@($result.Entries | Where-Object Level -CEQ 'Critical').Count -ge 1) "$case needs a Critical entry."
}

Assert-True ($null -ne (Get-Module SovereignTrust.Foundation) -and $null -ne (Get-Module SignalGraph)) 'Fresh-process module/manifest dependency did not load.'
Assert-True ((Get-Module SignalGraph).Path -like (Join-Path $siblingModuleRoot 'SignalGraph/*')) 'Foundation did not bind the sibling SignalGraph module.'
$script:condenser = & (Get-Module SovereignTrust.Foundation) { [SignalCondenser]::Start($null, $null) }
$item = New-Item 'ready'

foreach ($level in @('Information', 'Warning', 'Critical')) {
    $result = Invoke-Leaf 'Log' ([pscustomobject]@{ Level=$level; Message='literal [Memory.Item.Value|]' }) $item
    Assert-True (@($result.Entries).Count -eq 1 -and $result.Entries[0].Level -ceq $level -and $result.Entries[0].Message -ceq 'literal [Memory.Item.Value|]') "Log $level changed content or severity."
    if ($level -ceq 'Critical') { Assert-Failure $result 'Critical Log' }
    else { Assert-True (-not $result.Failure() -and $result.HasResult() -and $result.GetResult().Passed -and $result.GetResult().Level -ceq $level) "Log $level receipt failed." }
}
$pathLog = Invoke-Leaf 'Log' ([pscustomobject]@{ Level='Warning'; MessagePath='*.#.Subject.@' }) $item
Assert-True (-not $pathLog.Failure() -and $pathLog.Entries[0].Message -ceq 'ready') 'MessagePath did not preserve native string content.'
$maxLog = Invoke-Leaf 'Log' ([pscustomobject]@{ Level='Information'; Message=('m' * 2048) }) $item
Assert-True (-not $maxLog.Failure() -and $maxLog.Entries[0].Message.Length -eq 2048) 'Maximum permitted Log message failed.'

$badLogs = @(
    [pscustomobject]@{ Level='information'; Message='x' },
    [pscustomobject]@{ Level='Information' },
    [pscustomobject]@{ Level='Information'; Message='x'; MessagePath='*.#.Subject.@' },
    [pscustomobject]@{ Level='Information'; Message='' },
    [pscustomobject]@{ Level='Information'; Message=('x' * 2049) },
    [pscustomobject]@{ Level='Information'; MessagePath='*.#.Missing.@' },
    [pscustomobject]@{ Level='Information'; MessagePath='*.#.Subject.@.Missing' },
    [pscustomobject]@{ Level='Information'; MessagePath=('x' * 513) },
    [pscustomobject]@{ Level='Information'; Message='x'; Expected='forbidden' }
)
foreach ($config in $badLogs) { Assert-Failure (Invoke-Leaf 'Log' $config $item) 'Invalid Log' }
$newlineKey = "ready`n"
$newlineItem = New-Item @{ $newlineKey = 'ready' }
Assert-Failure (Invoke-Leaf 'Log' ([pscustomobject]@{ Level='Information'; MessagePath=("*.#.Subject.@.$newlineKey") }) $newlineItem) 'Newline MessagePath'
Assert-Failure (Invoke-Leaf 'Log' ([pscustomobject]@{ Level='Information'; MessagePath='*.#.Subject.@' }) (New-Item 42)) 'Nonstring MessagePath'
Assert-Failure (Invoke-Leaf 'log' ([pscustomobject]@{ Level='Information'; Message='x' }) $item) 'Unsupported activity'
foreach ($value in @($null, 42, $true, [object[]]@(), [object[]]@('ready'), [object[]]@('a','b'), [pscustomobject]@{ Text='ready' })) {
    $caseItem = New-Item $value
    $failed = Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath='*.#.Subject.@'; Predicate='IsString'; Message='Native string required' }) $caseItem
    Assert-Failure $failed 'Wrong native type'
    Assert-True (-not (@($failed.Entries | ForEach-Object Message) -join '|').Contains('System.Object')) 'Failure leaked object serialization.'
}
foreach ($predicate in @('IsString','IsNonBlankString','EqualsString')) {
    $config = [pscustomobject]@{ ValuePath='*.#.Subject.@'; Predicate=$predicate; Message='Must match' }
    if ($predicate -ceq 'EqualsString') { $config | Add-Member -NotePropertyName Expected -NotePropertyValue 'ready' }
    $passed = Invoke-Leaf 'Assert' $config $item
    Assert-True (-not $passed.Failure() -and $passed.HasResult() -and $passed.GetResult().Passed -and $passed.GetResult().Predicate -ceq $predicate) "Assert $predicate did not pass."
    Assert-True (@($passed.Entries).Count -eq 1 -and $passed.Entries[0].Level -ceq 'Information' -and $passed.Entries[0].Message -ceq 'Assertion passed.') "Assert $predicate pass entry differs."
}
Assert-Failure (Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath=("*.#.Subject.@.$newlineKey"); Predicate='IsString'; Message='Malformed path' }) $newlineItem) 'Newline ValuePath'
$contextFailure = Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath='*.#.Subject.@'; Predicate='IsString'; Message='Native string required' }) (New-Item 42)
Assert-Failure $contextFailure 'Typed failure context'
Assert-True ($contextFailure.Entries[0].Message -ceq 'Native string required [Path=*.#.Subject.@; Predicate=IsString]') 'Assert failure did not preserve exact bounded context.'
Assert-Failure (Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath='*.#.Subject.@'; Predicate='EqualsString'; Expected='Ready'; Message='Case mismatch' }) $item) 'Ordinal mismatch'
Assert-Failure (Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath='*.#.Subject.@'; Predicate='EqualsString'; Expected=42; Message='Wrong expected type' }) $item) 'Wrong Expected type'
Assert-Failure (Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath='*.#.Subject.@'; Predicate='EqualsString'; Message='Missing expected' }) $item) 'Absent Expected'
Assert-Failure (Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath='*.#.Subject.@'; Predicate='EqualsString'; Expected=('e' * 2049); Message='Oversize expected' }) $item) 'Oversize Expected'
Assert-Failure (Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath='*.#.Subject.@'; Predicate='IsString'; Expected='ready'; Message='Forbidden Expected' }) $item) 'Forbidden Expected'
Assert-Failure (Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath='*.#.Subject.@'; Predicate='isString'; Message='Bad predicate' }) $item) 'Case-sensitive Predicate'
Assert-Failure (Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath='*.#.Subject.@'; Predicate='IsString'; Message=('x' * 2049) }) $item) 'Oversize diagnostic'
Assert-Failure (Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath='*.#.Missing.@'; Predicate='IsString'; Message='Missing path' }) $item) 'Missing path'
Assert-Failure (Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath='*.#.Subject[0].@'; Predicate='IsString'; Message='Bad path syntax' }) $item) 'Unsupported path syntax'
Assert-Failure (Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath='*.#.Subject.@,fallback'; Predicate='IsString'; Message='Bad fallback syntax' }) $item) 'Fallback path syntax'
Assert-Failure (Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath='*.#.Subject.@.Text'; Predicate='IsString'; Message='Collection traversal' }) (New-Item ([object[]]@([pscustomobject]@{Text='ready'})))) 'Collection traversal'
$longText = 'e' * 2048
$longItem = New-Item $longText
$longPass = Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath='*.#.Subject.@'; Predicate='EqualsString'; Expected=$longText; Message=('m' * 2048) }) $longItem
Assert-True (-not $longPass.Failure()) 'Maximum permitted Expected/Message failed.'
$longPathPrefix = '*.#.Subject.@.'
$longKey = 'p' * (512 - $longPathPrefix.Length)
$longPathItem = New-Item @{ $longKey = 'ready' }
$longPathPass = Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath=($longPathPrefix + $longKey); Predicate='IsString'; Message='Long path' }) $longPathItem
Assert-True (-not $longPathPass.Failure()) 'Maximum permitted path failed.'
$longFailureItem = New-Item @{ $longKey = 42 }
$longFailure = Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath=($longPathPrefix + $longKey); Predicate='EqualsString'; Expected='42'; Message=('m' * 2048) }) $longFailureItem
Assert-Failure $longFailure 'Maximum failure diagnostic'
Assert-True ($longFailure.Entries[0].Message.Length -eq 2560 -and $longFailure.Entries[0].Message.EndsWith("[Path=$longPathPrefix$longKey; Predicate=EqualsString]")) 'Maximum failure entry exceeded bound or lost context.'
Assert-Failure (Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath=($longPathPrefix + $longKey + 'p'); Predicate='IsString'; Message='Oversize path' }) $longPathItem) 'Oversize ValuePath'
$blank = Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath='*.#.Subject.@'; Predicate='IsNonBlankString'; Message='Blank' }) (New-Item '  ')
Assert-Failure $blank 'Blank native string'
$sentinelItem = New-Item 42
$null = $sentinelItem.GetPointer().RegisterResultAsSignal('__Rejected__', 'ready')
Assert-Failure (Invoke-Leaf 'Assert' ([pscustomobject]@{ ValuePath='*.#.Subject.@'; Predicate='EqualsString'; Expected='42'; Message='Native type required' }) $sentinelItem) 'Caller-owned sentinel bypass'
Assert-True ($sentinelItem.GetPointer().Grid['Subject'].GetResult() -is [int]) 'Assert mutated the original subject.'

$bootstrap = [Signal]::Start('SignalCondenser.Bootstrap') | Select-Object -Last 1
$bootstrap.SetResult([pscustomobject]@{})
$started = New-Conductor -HostConductor $null -ConductionSignal $bootstrap | Select-Object -Last 1
Assert-True (-not $started.Failure() -and $started.HasResult()) 'Real mapped conductor did not initialize.'
$conductor = $started.GetResult()
$control = [Signal]::Start('Control') | Select-Object -Last 1
$null = $control.SetJacket($conductor.Signal)
$null = $control.SetPointer($conductor.Signal.GetPointer())
$run = [Signal]::Start('Run') | Select-Object -Last 1
$run.SetControl($control)
$null = $run.SetJacket($control)
$null = $run.SetPointer($conductor.Signal.GetPointer())

function Invoke-RealPhase([object[]]$steps, [Signal]$phaseItem) {
    $phase = [pscustomobject]@{ Name='TestPhase'; Steps=$steps }
    return & (Get-Module SovereignTrust.Foundation) { param($conduction,$item,$plan) Invoke-PlanPhase -ConductionSignal $conduction -ItemSignal $item -Phase $plan | Select-Object -Last 1 } $run $phaseItem $phase
}
$positiveSteps = @(
    [pscustomobject]@{ Name='RequireSubject'; Order=0; Adapter='Condenser.Signal'; Activity='Assert'; ExitAfterAdapter=$true; Config=[pscustomobject]@{ValuePath='*.#.Subject.@';Predicate='IsString';Message='Subject must be string'} },
    [pscustomobject]@{ Name='ReportWarning'; Order=1; Adapter='Condenser.Signal'; Activity='Log'; ExitAfterAdapter=$true; Config=[pscustomobject]@{Level='Warning';Message='validation passed'} },
    [pscustomobject]@{ Name='AfterWarning'; Order=2; Adapter='Condenser.Signal'; Activity='Log'; ExitAfterAdapter=$true; Config=[pscustomobject]@{Level='Information';Message='after warning'} }
)
$positive = Invoke-RealPhase $positiveSteps (New-Item 'ready')
Assert-True (-not $positive.Failure() -and (@($positive.Entries | Where-Object Message -CEQ 'validation passed').Count -eq 1)) 'Real mapped phase did not continue after passing Assert/Warning.'
Assert-True (@($positive.Entries | Where-Object Message -CEQ 'after warning').Count -eq 1) 'Real mapped phase did not continue after Warning.'
$negative = Invoke-RealPhase $positiveSteps (New-Item $true)
Assert-True ($negative.Failure() -and (@($negative.Entries | Where-Object Message -Like 'Subject must be string*').Count -eq 1)) 'Real mapped phase lost assertion failure.'
Assert-True (@($negative.Entries | Where-Object Message -CEQ 'validation passed').Count -eq 0) 'Real mapped phase ran later step after failure.'
$criticalSteps = @(
    [pscustomobject]@{ Name='Stop'; Order=0; Adapter='Condenser.Signal'; Activity='Log'; ExitAfterAdapter=$true; Config=[pscustomobject]@{Level='Critical';Message='stop plan'} },
    $positiveSteps[1]
)
$critical = Invoke-RealPhase $criticalSteps (New-Item 'ready')
Assert-True ($critical.Failure() -and (@($critical.Entries | Where-Object Message -CEQ 'stop plan').Count -eq 1)) 'Critical Log did not fail real mapped phase.'
Assert-True (@($critical.Entries | Where-Object Message -CEQ 'validation passed').Count -eq 0) 'Critical Log ran later step.'

$parentSteps = @(
    [pscustomobject]@{ Name='FirstPhase'; Order=0; Adapter='Condenser.Plan'; Activity='InvokePhase'; Path='*.#.FirstPhaseSteps.@'; ExitAfterAdapter=$true; Config=[pscustomobject]@{SkipRename=$true;PreventReclone=$false} },
    [pscustomobject]@{ Name='SecondPhase'; Order=1; Adapter='Condenser.Plan'; Activity='InvokePhase'; Path='*.#.SecondPhaseSteps.@'; ExitAfterAdapter=$true; Config=[pscustomobject]@{SkipRename=$true;PreventReclone=$false} }
)
$secondPhaseSteps = @([pscustomobject]@{ Name='SecondMarker'; Order=0; Adapter='Condenser.Signal'; Activity='Log'; ExitAfterAdapter=$true; Config=[pscustomobject]@{Level='Information';Message='second phase ran'} })
$parentPassItem = New-Item 'ready'
$null = $parentPassItem.GetPointer().RegisterResultAsSignal('FirstPhaseSteps', @($positiveSteps[0]))
$null = $parentPassItem.GetPointer().RegisterResultAsSignal('SecondPhaseSteps', $secondPhaseSteps)
$parentPass = Invoke-RealPhase $parentSteps $parentPassItem
Assert-True (-not $parentPass.Failure() -and @($parentPass.Entries | Where-Object Message -CEQ 'second phase ran').Count -eq 1) 'Real Foundation parent did not invoke second phase after success.'
$parentFailItem = New-Item 42
$null = $parentFailItem.GetPointer().RegisterResultAsSignal('FirstPhaseSteps', @($positiveSteps[0]))
$null = $parentFailItem.GetPointer().RegisterResultAsSignal('SecondPhaseSteps', $secondPhaseSteps)
$parentFail = Invoke-RealPhase $parentSteps $parentFailItem
Assert-True ($parentFail.Failure() -and @($parentFail.Entries | Where-Object Message -Like 'Subject must be string*').Count -eq 1) 'Real Foundation parent lost first-phase assertion failure.'
Assert-True (@($parentFail.Entries | Where-Object Message -CEQ 'second phase ran').Count -eq 0) 'Real Foundation parent invoked second phase after failure.'

$iterationItem = New-Item 'root'
$iterationGraph = $iterationItem.GetPointer()
$iterationSteps = @(
    [pscustomobject]@{ Name='RequireIteration'; Order=0; Adapter='Condenser.Signal'; Activity='Assert'; ExitAfterAdapter=$true; Config=[pscustomobject]@{ValuePath='*.#.Iteration.@';Predicate='IsString';Message='Iteration must be string'} },
    [pscustomobject]@{ Name='LaterIterationStep'; Order=1; Adapter='Condenser.Signal'; Activity='Log'; ExitAfterAdapter=$true; Config=[pscustomobject]@{Level='Information';Message='iteration passed'} }
)
$null = $iterationGraph.RegisterResultAsSignal('PhaseSteps', $iterationSteps)
$iterationPlan = [pscustomobject]@{
    Name='TestIterationPlan'; Adapter='Condenser.Plan'; Activity='IteratePhase'; Path='*.#.PhaseSteps.@'
    Config=[pscustomobject]@{
        Activity='InvokePhase'; IterationArray=@(42, 'ready'); IterationName='Iteration';
        Threading=[pscustomobject]@{Enabled=$false}; SkipRename=$true; PreventReclone=$false
    }
}
$iterationResult = & (Get-Module SovereignTrust.Foundation) {
    param($conduction,$item,$plan)
    Invoke-CondenserAdapter -Slot 'Plan' -Activity 'IteratePhase' -Signal $conduction -ItemSignal $item -Plan $plan | Select-Object -Last 1
} $run $iterationItem $iterationPlan
Assert-True ($iterationResult.Failure()) 'Real serial IteratePhase did not propagate failed assertion.'
Assert-True (@($iterationResult.Entries | Where-Object Message -Like 'Iteration must be string*').Count -eq 1) 'Real serial IteratePhase lost original diagnostic.'
Assert-True (@($iterationResult.Entries | Where-Object Message -CEQ 'iteration passed').Count -eq 0) 'Real serial IteratePhase ran later step or iteration.'
Assert-True ($iterationGraph.Grid['Iteration'].GetResult() -is [int]) 'Real serial IteratePhase advanced past first failed item.'

$serialPassItem = New-Item 'root'
$null = $serialPassItem.GetPointer().RegisterResultAsSignal('PhaseSteps', $iterationSteps)
$iterationPlan.Config.IterationArray = @('one','two')
$serialPass = & (Get-Module SovereignTrust.Foundation) {
    param($conduction,$item,$plan)
    Invoke-CondenserAdapter -Slot 'Plan' -Activity 'IteratePhase' -Signal $conduction -ItemSignal $item -Plan $plan | Select-Object -Last 1
} $run $serialPassItem $iterationPlan
Assert-True (-not $serialPass.Failure() -and @($serialPass.Entries | Where-Object Message -CEQ 'iteration passed').Count -eq 2) 'Real serial IteratePhase did not continue through two passing items.'
Assert-True ($serialPassItem.GetPointer().Grid['Iteration'].GetResult() -ceq 'two') 'Real serial IteratePhase did not reach second item.'

$serialCriticalItem = New-Item 'root'
$null = $serialCriticalItem.GetPointer().RegisterResultAsSignal('PhaseSteps', $criticalSteps)
$serialCritical = & (Get-Module SovereignTrust.Foundation) {
    param($conduction,$item,$plan)
    Invoke-CondenserAdapter -Slot 'Plan' -Activity 'IteratePhase' -Signal $conduction -ItemSignal $item -Plan $plan | Select-Object -Last 1
} $run $serialCriticalItem $iterationPlan
Assert-True ($serialCritical.Failure() -and @($serialCritical.Entries | Where-Object Message -CEQ 'stop plan').Count -eq 1) 'Real serial IteratePhase did not propagate Critical Log.'
Assert-True (@($serialCritical.Entries | Where-Object Message -CEQ 'validation passed').Count -eq 0) 'Real serial IteratePhase ran later step after Critical Log.'
Assert-True ($serialCriticalItem.GetPointer().Grid['Iteration'].GetResult() -ceq 'one') 'Real serial IteratePhase advanced after Critical Log.'

$catalogRoot = Join-Path $PSScriptRoot '../Src/PowerShell/Classes/Adapters/Catalog'
$catalogIndex = Get-Content (Join-Path $catalogRoot 'index.json') -Raw | ConvertFrom-Json
$mappedCatalog = Get-Content (Join-Path $catalogRoot 'Mapped/MappedCondenserAdapter.json') -Raw | ConvertFrom-Json
$leafCatalog = Get-Content (Join-Path $catalogRoot 'Condensers/SignalCondenser.json') -Raw | ConvertFrom-Json
$contract = Get-Content (Join-Path $PSScriptRoot '../Src/PowerShell/Classes/Adapters/ResultContracts/Condensers/SignalCondenser.json') -Raw | ConvertFrom-Json
Assert-True (@($catalogIndex.condensers | Where-Object name -CEQ 'SignalCondenser').Count -eq 1) 'Index discovery is not unique.'
Assert-True (@($mappedCatalog.concreteAdapters | Where-Object name -CEQ 'SignalCondenser').Count -eq 1) 'Mapped discovery is not unique.'
Assert-True ((@($leafCatalog.activities.name) -join ',') -ceq 'Log,Assert' -and (@($contract.activities.name) -join ',') -ceq 'Log,Assert') 'Catalog or result activity names differ.'
$indexEntry = @($catalogIndex.condensers | Where-Object name -CEQ 'SignalCondenser')[0]
$mappedEntry = @($mappedCatalog.concreteAdapters | Where-Object name -CEQ 'SignalCondenser')[0]
Assert-True ((Resolve-Path (Join-Path $catalogRoot $indexEntry.file)).ProviderPath -ceq (Resolve-Path (Join-Path $catalogRoot 'Condensers/SignalCondenser.json')).ProviderPath) 'Index reference does not resolve to leaf catalog.'
Assert-True ((Resolve-Path (Join-Path $catalogRoot ('Mapped/' + $mappedEntry.file))).ProviderPath -ceq (Resolve-Path (Join-Path $catalogRoot 'Condensers/SignalCondenser.json')).ProviderPath) 'Mapped reference does not resolve to leaf catalog.'
Assert-True ((Resolve-Path (Join-Path $catalogRoot ('Condensers/' + $leafCatalog.resultContractRef.file))).ProviderPath -ceq (Resolve-Path (Join-Path $PSScriptRoot '../Src/PowerShell/Classes/Adapters/ResultContracts/Condensers/SignalCondenser.json')).ProviderPath) 'Result contract reference does not resolve.'
foreach ($activity in $contract.activities) {
    $outcomes = @($activity.resultContract.variants[0].outcomes)
    Assert-True ($outcomes.Count -eq 2 -and @($outcomes | Where-Object { $_.signalState -ceq 'success' -and $_.hasResult }).Count -eq 1 -and @($outcomes | Where-Object { $_.signalState -ceq 'failure' -and -not $_.hasResult }).Count -eq 1) 'Result contract success/failure variants differ.'
}
$sourcePath = Join-Path $PSScriptRoot '../Src/PowerShell/Classes/Adapters/Condenser/SignalCondenser.ps1'
Assert-True ((Get-FileHash $sourcePath -Algorithm SHA256).Hash -ceq $contract.resultEvidence[0].sha256) 'Result evidence hash does not match implementation.'
foreach ($activity in $contract.activities) {
    foreach ($evidence in $activity.resultContract.variants[0].evidence) {
        $line = (Get-Content $sourcePath)[$evidence.line - 1]
        Assert-True ($line.Contains($evidence.symbol)) 'Result evidence line does not match implementation.'
    }
}

Write-Output "PASS: $script:assertions SignalCondenser assertions."
