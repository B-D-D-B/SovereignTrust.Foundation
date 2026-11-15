param([Parameter(Mandatory)][string]$NativeDirectory,[Parameter(Mandatory)][string]$Receipt)
$ErrorActionPreference='Stop'
if(Test-Path $Receipt){throw 'New receipt required'}
foreach($name in 'Microsoft.Extensions.Logging.Abstractions.dll','SignalGraph.dll','SovereignTrust.Foundation.dll'){
    [void][Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath((Join-Path $NativeDirectory $name))
}
. "$PSScriptRoot/../../Src/PowerShell.CSharp/Bootstrap/STNativeSignalCompatibility.ps1"
$ErrorActionPreference='Stop'
try {
$ErrorActionPreference = 'Stop'


$foundationRoot = Join-Path $PSScriptRoot '../../Src/PowerShell.CSharp'
. "$foundationRoot/Wrappers/Adapters/Invoke-CondenserAdapter.ps1"
. "$foundationRoot/Utilities/Adapters/Condenser/Plan/Resolve-ClonePlan.ps1"
. "$foundationRoot/Classes/Adapters/Condenser/PlanCondenser.ps1"

$script:assertions = 0
function Assert-True([bool]$Condition, [string]$Message) {
    $script:assertions++
    if (-not $Condition) { throw $Message }
}

$script:sequentialIndices = [System.Collections.Generic.List[int]]::new()
$script:poolCalls = [System.Collections.Generic.List[object]]::new()
$script:returnPoolError = $false

function Invoke-PlanIteration {
    param(
        $ConductionSignal,
        $ItemSignal,
        $Plan,
        $Iteration,
        [int]$IterationIndex,
        $IterationName,
        $IterationArray
    )

    $script:sequentialIndices.Add($IterationIndex)
    return [SignalGraph.Signal]::Start("Sequential:$IterationIndex") | Select-Object -Last 1
}

function Invoke-STRunspacePool {
    param(
        $Signal,
        $EnvironmentDefinition,
        $WorkItems,
        $WorkerCommand,
        $ThrottleLimit,
        $WorkerContext,
        [switch]$DebugInline,
        [int]$DebugWorkItemIndex
    )

    $script:poolCalls.Add([PSCustomObject]@{
        WorkItems      = @($WorkItems)
        WorkerCommand  = $WorkerCommand
        ThrottleLimit  = $ThrottleLimit
        WorkerContext  = $WorkerContext
        DebugInline     = $DebugInline.IsPresent
        DebugWorkItemIndex = $DebugWorkItemIndex
    })

    $poolSignal = [SignalGraph.Signal]::Start('StubPool') | Select-Object -Last 1
    $poolSignal.SetResult(@($WorkItems | ForEach-Object {
        $initializationSignal = [SignalGraph.Signal]::Start("Initialization:$($_.Index)") | Select-Object -Last 1
        $workerSignal = [SignalGraph.Signal]::Start("Worker:$($_.Index)") | Select-Object -Last 1
        if ($script:returnPoolError) {
            $null = $initializationSignal.LogInformation("Initialization diagnostic $($_.Index)")
            $null = $workerSignal.LogInformation("Worker diagnostic $($_.Index)")
        }

        [PSCustomObject]@{
            Index                = $_.Index
            InitializationSignal = $initializationSignal
            InitializationFailed = $false
            WorkerSignal         = $workerSignal
            WorkerFailed         = $false
            Error                = if ($script:returnPoolError) { "Runspace diagnostic $($_.Index)" } else { $null }
        }
    }))
    return $poolSignal
}

function New-TestContext([bool]$SupportParallelism, [int]$MaxParallelism) {
    $environment = [PSCustomObject]@{
        Config = [PSCustomObject]@{
            SupportParallelism = $SupportParallelism
            MaxParallelism     = $MaxParallelism
        }
    }

    $graph = ([SignalGraph.Graph]::Start('TestGraph', $null, $false) | Select-Object -Last 1).GetResult()
    $null = $graph.RegisterResultAsSignal('EnvironmentDetails', $environment)

    $conductionSignal = [SignalGraph.Signal]::Start('Conduction') | Select-Object -Last 1
    $null = $conductionSignal.SetPointer($graph)
    $itemSignal = [SignalGraph.Signal]::Start('Item') | Select-Object -Last 1
    $null = $itemSignal.SetPointer($graph)

    return [PSCustomObject]@{
        ConductionSignal = $conductionSignal
        ItemSignal       = $itemSignal
    }
}

function New-TestPlan([object]$Threading) {
    return [PSCustomObject]@{
        Name     = 'Iterate'
        Path     = '@'
        Adapter  = 'Condenser.Plan'
        Activity = 'IteratePhase'
        Config   = [PSCustomObject]@{
            Activity       = 'InvokePhase'
            IterationArray = @('A', 'B', 'C', 'D', 'E')
            IterationName  = 'CurrentItem'
            Threading      = $Threading
        }
    }
}

$condenser = New-Object PlanCondenser
$context = New-TestContext -SupportParallelism $true -MaxParallelism 3
$plan = New-TestPlan -Threading ([PSCustomObject]@{
    Enabled            = $true
    Warmup             = 2
    MaxThreads          = 4
    ReuseItemSignalGrid = $true
})

$result = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $plan, $context.ItemSignal)
Assert-True (-not $result.Failure()) 'Warmup/parallel split failed.'
Assert-True (($script:sequentialIndices -join ',') -eq '0,1') 'Warmup did not execute exactly the sequential prefix.'
Assert-True ($script:poolCalls.Count -eq 1) 'Parallel remainder was not submitted once.'
Assert-True ((($script:poolCalls[0].WorkItems.Index) -join ',') -eq '2,3,4') 'Parallel remainder contained the wrong indexes.'
Assert-True ($script:poolCalls[0].ThrottleLimit -eq 4) 'Plan MaxThreads was not honored.'
Assert-True ($script:poolCalls[0].WorkerCommand -eq 'Invoke-PlanIterationWorker') 'Wrong worker command was selected.'
Assert-True ($script:poolCalls[0].WorkerContext.ReuseItemSignalGrid) 'Grid reuse configuration was not forwarded.'

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$serialPlan = New-TestPlan -Threading ([PSCustomObject]@{ Enabled = $false; Warmup = -1; MaxThreads = 'invalid'; DebugWorkItemIndex = 'invalid'; DebugInline = 'invalid'; ReuseItemSignalGrid = 'invalid' })
$serialResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $serialPlan, $context.ItemSignal)
Assert-True (-not $serialResult.Failure()) 'Disabled threading validated unused settings.'
Assert-True (($script:sequentialIndices -join ',') -eq '0,1,2,3,4') 'Disabled threading did not execute every iteration sequentially.'
Assert-True ($script:poolCalls.Count -eq 0) 'Disabled threading unexpectedly started a runspace pool.'

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$disabledContext = New-TestContext -SupportParallelism $false -MaxParallelism 8
$disabledPlan = New-TestPlan -Threading ([PSCustomObject]@{ Enabled = $true; Warmup = 0; MaxThreads = 8 })
$disabledResult = $condenser.Invoke($null, 'IteratePhase', $disabledContext.ConductionSignal, $disabledPlan, $disabledContext.ItemSignal)
Assert-True (-not $disabledResult.Failure()) 'Global parallelism-disabled execution failed.'
Assert-True (($script:sequentialIndices -join ',') -eq '0,1,2,3,4') 'Global parallelism switch did not force sequential execution.'
Assert-True ($script:poolCalls.Count -eq 0) 'Global parallelism switch unexpectedly started a runspace pool.'

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$defaultPlan = New-TestPlan -Threading $null
$defaultResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $defaultPlan, $context.ItemSignal)
Assert-True (-not $defaultResult.Failure()) 'Default threading execution failed.'
Assert-True (($script:sequentialIndices -join ',') -eq '0,1,2,3,4') 'Missing Enabled did not default to sequential execution.'
Assert-True ($script:poolCalls.Count -eq 0) 'Missing Enabled unexpectedly started a runspace pool.'

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$defaultPlan = New-TestPlan -Threading ([PSCustomObject]@{ Enabled = $true })
$defaultResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $defaultPlan, $context.ItemSignal)
Assert-True (-not $defaultResult.Failure()) 'Enabled threading with default options failed.'
Assert-True ($script:sequentialIndices.Count -eq 0) 'Missing Warmup did not default to zero.'
Assert-True ((($script:poolCalls[0].WorkItems.Index) -join ',') -eq '0,1,2,3,4') 'Default threading did not submit the complete array.'
Assert-True ($script:poolCalls[0].ThrottleLimit -eq 3) 'Default threading did not use environment MaxParallelism.'
Assert-True (-not $script:poolCalls[0].WorkerContext.ReuseItemSignalGrid) 'Grid reuse did not default to false.'
Assert-True (-not $script:poolCalls[0].DebugInline) 'Inline debugging did not default to false.'
Assert-True ($script:poolCalls[0].DebugWorkItemIndex -eq 0) 'Debug index did not default to the first remaining iteration.'

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$explicitDisabledPlan = New-TestPlan -Threading ([PSCustomObject]@{ Enabled = $false; Warmup = 0; DebugInline = $true; MaxThreads = 8 })
$explicitDisabledResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $explicitDisabledPlan, $context.ItemSignal)
Assert-True (-not $explicitDisabledResult.Failure()) 'Explicit threading-disabled execution failed.'
Assert-True (($script:sequentialIndices -join ',') -eq '0,1,2,3,4') 'Enabled false did not force sequential execution.'
Assert-True ($script:poolCalls.Count -eq 0) 'Inline debugging bypassed Enabled false.'

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$inlinePlan = New-TestPlan -Threading ([PSCustomObject]@{
    Enabled           = $true
    Warmup            = 1
    MaxThreads         = 1
    DebugInline        = $true
    DebugWorkItemIndex = 3
})
$inlineResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $inlinePlan, $context.ItemSignal)
Assert-True (-not $inlineResult.Failure()) 'Inline debugging dispatch failed.'
Assert-True (($script:sequentialIndices -join ',') -eq '0') 'Inline debugging did not retain the warmup prefix.'
Assert-True ($script:poolCalls.Count -eq 1) 'Inline debugging did not dispatch through the runspace helper.'
Assert-True ($script:poolCalls[0].DebugInline) 'Inline debugging configuration was not forwarded.'
Assert-True ($script:poolCalls[0].DebugWorkItemIndex -eq 3) 'Inline debugging work-item index was not forwarded.'

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$clampedPlan = New-TestPlan -Threading ([PSCustomObject]@{ Enabled = $true; Warmup = 99; MaxThreads = 8 })
$clampedResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $clampedPlan, $context.ItemSignal)
Assert-True (-not $clampedResult.Failure()) 'Clamped warmup execution failed.'
Assert-True (($script:sequentialIndices -join ',') -eq '0,1,2,3,4') 'Warmup was not clamped to the iteration count.'
Assert-True ($script:poolCalls.Count -eq 0) 'Clamped warmup unexpectedly started a runspace pool.'

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$script:returnPoolError = $true
$diagnosticPlan = New-TestPlan -Threading ([PSCustomObject]@{ Enabled = $true; Warmup = 0; MaxThreads = 2 })
$diagnosticResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $diagnosticPlan, $context.ItemSignal)
$diagnosticMessages = @($diagnosticResult.Entries | ForEach-Object { [string]$_.Message })
Assert-True ($diagnosticResult.Failure()) 'Runspace error did not fail the plan iteration.'
Assert-True ($diagnosticMessages -contains 'Initialization diagnostic 0') 'Runspace error discarded initialization diagnostics.'
Assert-True ($diagnosticMessages -contains 'Worker diagnostic 0') 'Runspace error discarded worker diagnostics.'
Assert-True (($diagnosticMessages | Where-Object { $_ -like '*Runspace diagnostic 0*' }).Count -gt 0) 'Runspace error message was not logged.'
$script:returnPoolError = $false

foreach ($invalidThreading in @(
    @{ Enabled = 'false' },
    @{ Enabled = $true; Warmup = 'invalid' },
    @{ Enabled = $true; Warmup = -1 },
    @{ Enabled = $true; Warmup = -2 },
    @{ Enabled = $true; MaxThreads = 'invalid' },
    @{ Enabled = $true; DebugWorkItemIndex = 'invalid' },
    @{ Enabled = $true; DebugInline = 'false' },
    @{ Enabled = $true; ReuseItemSignalGrid = 'false' }
)) {
    $script:sequentialIndices.Clear()
    $script:poolCalls.Clear()
    $invalidPlan = New-TestPlan -Threading $invalidThreading
    $invalidResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $invalidPlan, $context.ItemSignal)
    Assert-True ($invalidResult.Failure()) 'Invalid threading configuration did not fail validation.'
    Assert-True ($script:sequentialIndices.Count -eq 0 -and $script:poolCalls.Count -eq 0) 'Invalid configuration dispatched iterations.'
}

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$missingEnvironmentContext = New-TestContext -SupportParallelism $true -MaxParallelism 3
$null = $missingEnvironmentContext.ConductionSignal.SetPointer(([SignalGraph.Graph]::Start('EmptyGraph', $null, $false) | Select-Object -Last 1).GetResult())
$missingEnvironmentPlan = New-TestPlan -Threading @{ Enabled = $true }
$missingEnvironmentResult = $condenser.Invoke($null, 'IteratePhase', $missingEnvironmentContext.ConductionSignal, $missingEnvironmentPlan, $missingEnvironmentContext.ItemSignal)
Assert-True (-not $missingEnvironmentResult.Failure()) 'Missing environment defaults failed.'
Assert-True (($script:sequentialIndices -join ',') -eq '0,1,2,3,4') 'Missing environment did not default to sequential execution.'
Assert-True ($script:poolCalls.Count -eq 0) 'Missing environment unexpectedly started a pool.'

$serialOnlyContext = New-TestContext -SupportParallelism $true -MaxParallelism 3
$serialEnvironment = $serialOnlyContext.ConductionSignal.GetPointer().Grid['EnvironmentDetails'].GetResult()
$serialEnvironment.Config.MaxParallelism = 'invalid'
$serialEnvironment.Config.SupportParallelism = 'invalid'
foreach ($serialSettings in @($null, @{}, @{ Warmup = 'invalid'; DebugInline = 'invalid' }, @{ Enabled = $false; MaxThreads = 'invalid' })) {
    $script:sequentialIndices.Clear()
    $script:poolCalls.Clear()
    $serialOnlyPlan = New-TestPlan -Threading $serialSettings
    $serialOnlyResult = $condenser.Invoke($null, 'IteratePhase', $serialOnlyContext.ConductionSignal, $serialOnlyPlan, $serialOnlyContext.ItemSignal)
    Assert-True (-not $serialOnlyResult.Failure()) 'Serial-only execution inspected unused environment/threading settings.'
    Assert-True (($script:sequentialIndices -join ',') -eq '0,1,2,3,4') 'Serial-only execution skipped or duplicated iterations.'
    Assert-True ($script:poolCalls.Count -eq 0) 'Serial-only execution dispatched workers.'
}

$script:sequentialIndices.Clear()
$script:poolCalls.Clear()
$singlePlan = New-TestPlan -Threading @{ Enabled = $true }
$singlePlan.Config.IterationArray = @('A')
$singleResult = $condenser.Invoke($null, 'IteratePhase', $context.ConductionSignal, $singlePlan, $context.ItemSignal)
Assert-True (-not $singleResult.Failure()) 'Single-item serial fallback failed.'
Assert-True (($script:sequentialIndices -join ',') -eq '0' -and $script:poolCalls.Count -eq 0) 'Single-item fallback did not execute exactly once.'

# Selection spies retain actual values/context and call the real clone helper.
$script:selectedCalls = [System.Collections.Generic.List[object]]::new()
$script:cloneCount = 0
$script:realClone = ${function:Resolve-ClonePlan}
function Resolve-ClonePlan { param($Plan) $script:cloneCount++; & $script:realClone -Plan $Plan }
function Invoke-PlanIteration {
    param($ConductionSignal, $ItemSignal, $Plan, $Iteration, [int]$IterationIndex, $IterationName, $IterationArray)
    $script:sequentialIndices.Add($IterationIndex)
    $script:selectedCalls.Add([pscustomobject]@{ Value=$Iteration; Index=$IterationIndex; Name=$IterationName; Array=$IterationArray })
    $null = Resolve-ClonePlan -Plan $Plan
    [SignalGraph.Signal]::Start("Selected:$IterationIndex") | Select-Object -Last 1
}
function Invoke-SelectionCase($Items, [hashtable]$Settings, [object]$Threading = $null, $TestContext = $context) {
    $script:sequentialIndices.Clear(); $script:poolCalls.Clear(); $script:selectedCalls.Clear(); $script:cloneCount=0
    $testPlan=New-TestPlan -Threading $Threading
    $testPlan.Config.IterationArray=$Items
    foreach($setting in $Settings.Keys) { $testPlan.Config | Add-Member -NotePropertyName $setting -NotePropertyValue $Settings[$setting] }
    return $condenser.Invoke($null,'IteratePhase',$TestContext.ConductionSignal,$testPlan,$TestContext.ItemSignal)
}
function Assert-SelectionFailure($Items, [hashtable]$Settings) {
    $failed=Invoke-SelectionCase $Items $Settings @{Enabled=$true; Warmup=0}
    Assert-True ($failed.Failure()) "Invalid selection accepted: context=$script:selectionFailureContext,count=$(@($Items).Count),settings=$($Settings | ConvertTo-Json -Compress)"
    Assert-True ($failed.Level -eq 'Critical') 'Selection failure lost Critical status.'
    Assert-True ($script:cloneCount -eq 0 -and $script:selectedCalls.Count -eq 0 -and $script:poolCalls.Count -eq 0) 'Invalid selection cloned or dispatched records.'
}
$records=@(
    [pscustomobject]@{Id='C';Meta=[pscustomobject]@{Rank=3};Keep=$true},
    [pscustomobject]@{Id='A';Meta=[pscustomobject]@{Rank=1};Keep=$false},
    [pscustomobject]@{Id='B';Meta=[pscustomobject]@{Rank=2};Keep=$true},
    [pscustomobject]@{Id='B2';Meta=[pscustomobject]@{Rank=2};Keep=$true}
)
foreach($case in @(
    @{S=@{}; E='C,A,B,B2'}, @{S=@{OrderDirection=' desc '};E='C,A,B,B2'},
    @{S=@{OrderBy=' Meta.Rank '};E='C,B,B2,A'}, @{S=@{OrderBy='Meta.Rank';OrderDirection=$null};E='C,B,B2,A'},
    @{S=@{OrderBy='Meta.Rank';OrderDirection='ASC'};E='A,B,B2,C'}, @{S=@{OrderBy='Meta.Rank';OrderDirection='desc'};E='C,B,B2,A'},
    @{S=@{OrderBy='Meta.Rank';OrderDirection='ASC';Limit=2};E='A,B'}, @{S=@{OrderBy='Meta.Rank';OrderDirection='DESC';Limit=2};E='C,B'},
    @{S=@{Limit=2};E='C,A'}, @{S=@{Limit=0};E=''}, @{S=@{Limit=1};E='C'},
    @{S=@{Limit=4};E='C,A,B,B2'}, @{S=@{Limit=5};E='C,A,B,B2'}, @{S=@{Limit=[long]::MaxValue};E='C,A,B,B2'},
    @{S=@{OrderBy=$null;OrderDirection=$null;Limit=$null};E='C,A,B,B2'}
)) {
    $outcome=Invoke-SelectionCase $records $case.S
    Assert-True (-not $outcome.Failure()) 'Valid order/limit case failed.'
    Assert-True (($script:selectedCalls.Value.Id -join ',') -ceq $case.E) "Wrong selection, expected $($case.E)."
    Assert-True ($script:cloneCount -eq $script:selectedCalls.Count) 'Selection clone count differs.'
    for($i=0;$i -lt $script:selectedCalls.Count;$i++) {
        $call=$script:selectedCalls[$i]
        Assert-True ($call.Index -eq $i -and $call.Name -eq 'CurrentItem' -and ($call.Array.Id -join ',') -ceq $case.E) 'Serial selected context differs.'
    }
}
Assert-True (($records.Id -join ',') -ceq 'C,A,B,B2' -and (($records | ForEach-Object { $_.Meta.Rank }) -join ',') -eq '3,1,2,2') 'Caller input mutated.'
$nullRecords=@([pscustomobject]@{Id='N';Meta=$null},$records[0],[pscustomobject]@{Id='M'},$records[2],$records[3])
foreach($direction in @('ASC','DESC')) {
    $r=Invoke-SelectionCase $nullRecords @{OrderBy='Meta.Rank';OrderDirection=$direction}
    $expected=if($direction -eq 'ASC'){'B,B2,C,N,M'}else{'C,B,B2,N,M'}
    Assert-True (-not $r.Failure() -and ($script:selectedCalls.Value.Id -join ',') -ceq $expected) 'Null bucket or stable ties differ.'
    $r=Invoke-SelectionCase @([pscustomobject]@{Id='N';Rank=$null},[pscustomobject]@{Id='M'}) @{OrderBy='Rank';OrderDirection=$direction}
    Assert-True (-not $r.Failure() -and ($script:selectedCalls.Value.Id -join ',') -eq 'N,M') 'All-null order differs.'
}
$invalidFiltered=[pscustomobject]@{Id='X';Meta=[pscustomobject]@{Rank=[pscustomobject]@{Invalid=1}};Keep=$false}
$r=Invoke-SelectionCase @($records+$invalidFiltered) @{Filter='Keep|false';OrderBy='Meta.Rank';OrderDirection='ASC';Limit=2}
Assert-True (-not $r.Failure() -and ($script:selectedCalls.Value.Id -join ',') -eq 'B,B2') 'Filter did not precede ordering/limit.'
foreach($items in @(@(),@($records[0]))) {
    $r=Invoke-SelectionCase $items @{OrderBy='Meta.Rank';Limit=1}
    Assert-True (-not $r.Failure() -and $script:selectedCalls.Count -eq $items.Count) 'Empty/singleton selection differs.'
}
$nested=@(@{Id='D';meta=[ordered]@{RANK=2}},[pscustomobject]@{Id='P';Meta=[pscustomobject]@{Rank=1}})
$r=Invoke-SelectionCase $nested @{OrderBy='META.rank';OrderDirection='ASC'}
Assert-True (-not $r.Failure() -and ($script:selectedCalls.Value.Id -join ',') -eq 'P,D') 'Dictionary/NoteProperty case matching differs.'
foreach($case in @(@{Items=@('b','A','a');Expected='A,a,b'},@{Items=@($true,$false,$false);Expected='False,False,True'})) {
    $valueRecords=@($case.Items | ForEach-Object { [pscustomobject]@{Value=$_} })
    $r=Invoke-SelectionCase $valueRecords @{OrderBy='Value';OrderDirection='ASC'}
    Assert-True (-not $r.Failure() -and ($script:selectedCalls.Value.Value -join ',') -ceq $case.Expected) 'Resolved key category comparison differs.'
}
$tiny=[decimal]::Parse('0.0000000000000000000000000001',[cultureinfo]::InvariantCulture)
$numeric=@([decimal]::MaxValue,[uint64]::MaxValue,[int64]::MinValue,[decimal]::MinValue,$tiny,[decimal]::Zero)
$numericAsc=@([decimal]::MinValue,[int64]::MinValue,[decimal]::Zero,$tiny,[uint64]::MaxValue,[decimal]::MaxValue)
foreach($direction in @('ASC','DESC')) {
    $expected=@($numericAsc); if($direction -eq 'DESC'){[array]::Reverse($expected)}
    foreach($limit in @(1,6)) {
        $r=Invoke-SelectionCase @($numeric | ForEach-Object { [pscustomobject]@{Value=$_} }) @{OrderBy='Value';OrderDirection=$direction;Limit=$limit}
        Assert-True (-not $r.Failure() -and $script:selectedCalls.Count -eq $limit) 'Exact numeric boundary selection failed.'
        for($i=0;$i -lt $limit;$i++){Assert-True ([decimal]$script:selectedCalls[$i].Value.Value -eq [decimal]$expected[$i]) 'Numeric precision/order lost.'}
    }
}
$ties=@([pscustomobject]@{Id='I';Rank=[int]1},[pscustomobject]@{Id='D';Rank=[decimal]1},[pscustomobject]@{Id='U';Rank=[uint64]1})
$r=Invoke-SelectionCase $ties @{OrderBy='Rank';OrderDirection='DESC'}
Assert-True (-not $r.Failure() -and ($script:selectedCalls.Value.Id -join ',') -eq 'I,D,U') 'Exact numeric ties unstable.'
# Current source admits Double; candidate repairs only the nonexistent comparison API.
foreach($floating in @(@([double]1.0000000000000002,[double]1),@([double]1e-29,[double]0),@([double]::NaN),@([double]::PositiveInfinity),@([double]::NegativeInfinity))) {
    foreach($direction in @('ASC','DESC')) { foreach($limit in @(0,1)) {
        $r=Invoke-SelectionCase @($floating|ForEach-Object{[pscustomobject]@{Value=$_}}) @{OrderBy='Value';OrderDirection=$direction;Limit=$limit}
        Assert-True (-not $r.Failure() -and $script:selectedCalls.Count -eq $limit) 'Current Double admission/Limit behavior differs.'
    } }
}
Assert-SelectionFailure @([pscustomobject]@{Value=[single]1}) @{OrderBy='Value';Limit=0}
foreach($direction in @('ASC','DESC')){
    $values=@([pscustomobject]@{Id='NaN1';Value=[double]::NaN},[pscustomobject]@{Id='High';Value=[double]::PositiveInfinity},[pscustomobject]@{Id='Low';Value=[double]::NegativeInfinity},[pscustomobject]@{Id='NaN2';Value=[double]::NaN},[pscustomobject]@{Id='Finite';Value=[double]1.25},[pscustomobject]@{Id='Null';Value=$null})
    $r=Invoke-SelectionCase $values @{OrderBy='Value';OrderDirection=$direction}
    $expected=if($direction -eq 'ASC'){'NaN1,NaN2,Low,Finite,High,Null'}else{'High,Finite,Low,NaN1,NaN2,Null'}
    Assert-True (-not $r.Failure() -and ($script:selectedCalls.Value.Id -join ',') -ceq $expected) 'Documented candidate Double.CompareTo/NaN/null/tie ordering differs.'
}
foreach($settings in @(@{OrderBy='@'},@{OrderBy=1},@{OrderBy=''},@{OrderBy=' '},@{OrderBy='Rank..Child'},@{OrderBy='Rank[0]'},@{OrderBy='Rank |false'},@{OrderBy='*.Rank'},@{OrderBy='Rank,Id'},@{OrderBy='Rank .Child'},@{OrderBy='$(throw 1)'},@{OrderDirection='sideways'},@{OrderDirection=1},@{Limit=-1},@{Limit=$true},@{Limit='2'},@{Limit=[double]2},@{Limit=@(1)},@{Limit=@{n=1}})) {
    Assert-SelectionFailure $records $settings
    Assert-SelectionFailure @() $settings
}
$script:getterCalls=0
$getter=[pscustomobject]@{}
$getter | Add-Member ScriptProperty Rank { $script:getterCalls++; throw 'Shared getter observation' }
Add-Type -TypeDefinition 'public class OrderingGetterProbe { public static int Calls; public int Rank { get { Calls++; throw new System.Exception("Shared getter observation"); } } } public class OrderingMethodProbe { public static int Calls; public int GetRank() { Calls++; return 2; } } public class OrderingConfigProbe { public object[] IterationArray { get; set; } public string IterationName { get { return "CurrentItem"; } } public string OrderBy { get { throw new System.Exception("Config getter observation"); } } }'
$clr=[OrderingGetterProbe]::new()
$ambiguous=[hashtable]::new([StringComparer]::Ordinal);$ambiguous.Add('Rank',1);$ambiguous.Add('rank',2)
foreach($case in @(@{Item=$clr;Path='Rank'},@{Item=[pscustomobject]@{Meta=$clr};Path='Meta.Rank'},@{Item=[pscustomobject]@{Rank=@{a=1}};Path='Rank'},@{Item=[System.Collections.Generic.Dictionary[string,object]]::new();Path='Rank'})) {
    $script:selectionFailureContext=$case.Item.GetType().FullName
    foreach($limit in @(0,1)) { Assert-SelectionFailure @($case.Item) @{OrderBy=$case.Path;Limit=$limit} }
}
Assert-True ([OrderingGetterProbe]::Calls -eq 4) 'Shared resolver did not execute root/nested CLR getters.'
$r=Invoke-SelectionCase @($getter) @{OrderBy='Rank';Limit=0}
Assert-True (-not $r.Failure() -and $script:getterCalls -eq 1 -and $script:cloneCount -eq 0 -and $script:poolCalls.Count -eq 0) 'Shared ScriptProperty no-result/null semantics differ.'
Assert-True (@($r.Entries | Where-Object { $null -ne $_.Exception }).Count -eq 0) 'ScriptProperty probe unexpectedly exposed a structured exception.'
foreach($case in @(@{Item=[pscustomobject]@{Rank=1};Path='Rank.Child'},@{Item=$ambiguous;Path='Rank'},@{Item=$null;Path='Rank'})) {
    $r=Invoke-SelectionCase @($case.Item) @{OrderBy=$case.Path;Limit=0}
    Assert-True (-not $r.Failure() -and $script:cloneCount -eq 0) 'Unreported shared traversal result did not remain nullable.'
}
$method=[OrderingMethodProbe]::new()
$r=Invoke-SelectionCase @($method,[pscustomobject]@{Rank=1}) @{OrderBy='Rank';OrderDirection='ASC'}
Assert-True (-not $r.Failure() -and [OrderingMethodProbe]::Calls -eq 1 -and [object]::ReferenceEquals($script:selectedCalls[1].Value,$method)) 'Method-backed shared key was not used for ordering.'
$badPlan=New-TestPlan -Threading $null
$badPlan.Config=[OrderingConfigProbe]::new();$badPlan.Config.IterationArray=$records
$script:cloneCount=0;$script:selectedCalls.Clear();$script:poolCalls.Clear()
$r=$condenser.Invoke($null,'IteratePhase',$context.ConductionSignal,$badPlan,$context.ItemSignal)
Assert-True ($r.Failure() -and @($r.Entries|Where-Object {$null -ne $_.Exception}).Count -gt 0 -and $script:cloneCount -eq 0 -and $script:selectedCalls.Count -eq 0 -and $script:poolCalls.Count -eq 0) 'Configuration structured exception escaped pre-dispatch failure.'
foreach($items in @(@(1,'1'),@($false,1),@([pscustomobject]@{a=1}))) { Assert-SelectionFailure @($items | ForEach-Object { [pscustomobject]@{Value=$_} }) @{OrderBy='Value';Limit=0} }
$r=Invoke-SelectionCase @([pscustomobject]@{Rank=@{Nested=1}},[double]1,[DayOfWeek]::Monday) @{Limit=2}
Assert-True (-not $r.Failure() -and $script:selectedCalls.Count -eq 2) 'Omitted ordering imposed key restrictions.'
# Final selected array is shared by warmup, worker context and contiguous work indexes.
foreach($mode in @(@{Enabled=$true;Warmup=1;MaxThreads=3},@{Enabled=$true;Warmup=1;MaxThreads=1;DebugInline=$true})) {
    $r=Invoke-SelectionCase $records @{OrderBy='Meta.Rank';OrderDirection='ASC';Limit=3} $mode
    Assert-True (-not $r.Failure() -and ($script:selectedCalls.Value.Id -join ',') -eq 'A') 'Selected warmup differs.'
    $pool=$script:poolCalls[0]
    Assert-True (($pool.WorkItems.Value.Id -join ',') -eq 'B,B2' -and ($pool.WorkItems.Index -join ',') -eq '1,2') 'Pool selected values/indexes differ.'
    Assert-True (($pool.WorkerContext.IterationArray.Id -join ',') -eq 'A,B,B2' -and $pool.WorkerContext.IterationName -eq 'CurrentItem' -and ($script:selectedCalls[0].Array.Id -join ',') -eq 'A,B,B2') 'Warmup/pool context differs.'
    Assert-True ($script:cloneCount -eq 3) 'Excluded records were cloned.'
}
foreach($limit in @(0,1)) {
    $r=Invoke-SelectionCase $records @{OrderBy='Meta.Rank';OrderDirection='ASC';Limit=$limit} @{Enabled=$true;Warmup=5;MaxThreads=3}
    Assert-True (-not $r.Failure() -and $script:poolCalls.Count -eq 0 -and $script:cloneCount -eq $limit) 'Limit below warmup cloned/dispatched excluded records.'
}
foreach($testContext in @($context,$disabledContext)) {
    $r=Invoke-SelectionCase $records @{OrderBy='Meta.Rank';OrderDirection='ASC';Limit=1} @{Enabled=$true;Warmup=0;MaxThreads=3} $testContext
    Assert-True (-not $r.Failure() -and $script:poolCalls.Count -eq 0 -and $script:selectedCalls[0].Value.Id -eq 'A') 'Selected singleton/global fallback differs.'
}
Write-Output "PASS: $script:assertions IteratePhase assertions (existing regressions; shared key resolution, Desc default, exact numerics, clone/dispatch boundaries and context)."

$report=[ordered]@{Scope='Adapted original IteratePhase regression; unit dispatch spies, not actual worker proof';OriginalTestsSha256='B5D6BAA7D609D42443EACDC667655C66700715C90B9AB1B6981FA0914ED4A92D';PassCount=$script:assertions;FailCount=0;SkipCount=0;Total=$script:assertions;CoreSha256=(Get-FileHash (Join-Path $NativeDirectory SovereignTrust.Foundation.dll)).Hash}
$report|ConvertTo-Json -Depth 5|Set-Content $Receipt -Encoding utf8NoBOM
"$($script:assertions)/0/$($script:assertions) skip0"
} catch {
[ordered]@{Scope='Adapted IteratePhase regression';PassCount=$script:assertions-1;FailCount=1;Total=$script:assertions;SkipCount=0;Error=$_.Exception.Message}|ConvertTo-Json|Set-Content $Receipt -Encoding utf8NoBOM
throw
}