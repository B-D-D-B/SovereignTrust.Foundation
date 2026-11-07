using module ../Src/PowerShell/SovereignTrust.Foundation.psd1
param([Parameter(Mandatory)][string]$ConfigPath)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Src/PowerShell/SovereignTrust.Foundation.psd1') -Force

class RemainingRRProbe {
    static [int]$Count = 0
    [object]$Jacket
    [object] Construct([object]$jacket) {
        [RemainingRRProbe]::Count++
        $this.Jacket = $jacket
        return & (Get-Module SovereignTrust.Foundation) {
            $signalType = 'Signal' -as [type]
            $s = $signalType::Start('RemainingRRProbe.Construct') | Select-Object -Last 1
            $s.SetResult($true)
            return $s
        }
    }
}
class RemainingRRMerge {
    [object]$Overlay
    [int]$Count = 0
    [bool]$Fail = $false
    [object] Invoke([object]$slot,[object]$activity,[object]$signal,[object]$plan,[object]$itemSignal) {
        $this.Count++
        if ($this.Fail) {
            return & (Get-Module SovereignTrust.Foundation) {
                $signalType = 'Signal' -as [type]
                return $signalType::Start('RemainingRRMergeFailure').LogCritical('Synthetic merge failure.')
            }
        }
        $merged = $this.Overlay | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
        if ($null -eq $this.Overlay) { throw 'Mock merge overlay absent.' }
        if ($null -eq $merged.PSObject.Properties['Addresses']) { $merged | Add-Member NoteProperty Addresses @('manifest-default') }
        else { $merged.Addresses = @($merged.Addresses) + @('manifest-tail') }
        return & (Get-Module SovereignTrust.Foundation) {
            $signalType = 'Signal' -as [type]
            $s = $signalType::Start('RemainingRRMockMerge') | Select-Object -Last 1
            $s.SetResult($args[0]); return $s
        } $merged
    }
}

function Assert([bool]$ok, [string]$message) { if (-not $ok) { throw $message } }
function Copy-Value($value) { return ($value | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json -Depth 100) }
$passed = 0
$data = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -Depth 100
$slots = @($data.Agents[0].Roles[0].Adapters)
Assert ($slots.Count -eq 21) 'Config slot count changed.'; $passed++
$families = [ordered]@{
    Telemetry = @('AzureApplicationInsights','InstrumentationKey','instrumentation')
    TestQueue = @('AzureStorageQueue','QueuePath','queue')
    'Data-Media' = @('AzureDataExplorer','Database','database')
    TestSqlDatabase = @('AzureSql','Database','database')
    TestADXDatabase = @('AzureDataExplorer','Database','database')
    ST_Conduction_ST = @('Conduction_ST',$null,$null)
}
Assert (@($slots | Where-Object { $_.Name -notin @($families.Keys) -and $_.SchemaVersion -eq 2 }).Count -eq 13) 'Existing v2 count changed.'; $passed++
Assert (@($slots | Where-Object Name -in @('SDATokens','SDAMedia')).Count -eq 2) 'Config-only count changed.'; $passed++

foreach ($name in $families.Keys) {
    $family,$field,$key = $families[$name]
    $slot = $slots | Where-Object Name -eq $name | Select-Object -First 1
    Assert ($slot.SchemaVersion -eq 2 -and $slot.Routes -is [array]) "$name is not v2."; $passed++
    $source = $slot | ConvertTo-Json -Depth 100 -Compress
    $normalized = Resolve-RemainingResourceRoutesJacket -Jacket $slot -Family $family -AllowUnresolved | Select-Object -Last 1
    Assert ($normalized.Success() -and $normalized.HasResult()) "$name did not normalize."; $passed++
    $value = $normalized.GetResult()
    Assert (($slot | ConvertTo-Json -Depth 100 -Compress) -ceq $source) "$name source mutated."; $passed++
    $expected = @($slot.Routes | ForEach-Object Address)
    Assert ((@($value.Addresses) -join [char]0) -ceq ($expected -join [char]0)) "$name route order/value changed."; $passed++
    if ($null -ne $field) {
        Assert ($value.Resource -ceq $slot.Resource[0].$field -and $slot.Resource[0].Key -ceq $key -and $slot.Routes[0].ResourceKey -ceq $key) "$name resource projection changed."; $passed++
    }
    $legacy = [pscustomobject]@{ Addresses = $expected; Resource = 'legacy' }
    $legacyResult = Resolve-RemainingResourceRoutesJacket -Jacket $legacy -Family $family | Select-Object -Last 1
    Assert ($legacyResult.Success() -and [object]::ReferenceEquals($legacyResult.GetResult(),$legacy)) "$name v1 changed."; $passed++

    $mixed = Copy-Value $slot; $mixed | Add-Member NoteProperty Addresses @('mixed')
    Assert ((Resolve-RemainingResourceRoutesJacket -Jacket $mixed -Family $family -AllowUnresolved).Failure()) "$name mixed v2 accepted."; $passed++
    $wrong = Copy-Value $slot; $wrong.Routes[0].Key = 'wrong'
    Assert ((Resolve-RemainingResourceRoutesJacket -Jacket $wrong -Family $family).Failure()) "$name wrong route accepted."; $passed++
    $extra = Copy-Value $slot; $extra.Routes[0] | Add-Member NoteProperty ApiKind $null
    Assert ((Resolve-RemainingResourceRoutesJacket -Jacket $extra -Family $family).Failure()) "$name extra route field accepted."; $passed++
    $arrayKey = Copy-Value $slot; $arrayKey.Routes[0].Key = @($slot.Routes[0].Key)
    Assert ((Resolve-RemainingResourceRoutesJacket -Jacket $arrayKey -Family $family).Failure()) "$name array Route Key accepted."; $passed++
    $nullVersion = Copy-Value $slot; $nullVersion.SchemaVersion = $null
    Assert ((Resolve-RemainingResourceRoutesJacket -Jacket $nullVersion -Family $family).Failure()) "$name null SchemaVersion accepted."; $passed++
    $wrongCase = Copy-Value $slot; $wrongCase.PSObject.Properties.Remove('SchemaVersion'); $wrongCase | Add-Member NoteProperty schemaVersion 2
    Assert ((Resolve-RemainingResourceRoutesJacket -Jacket $wrongCase -Family $family).Failure()) "$name wrong-case SchemaVersion accepted."; $passed++
    foreach ($reserved in @('Routes','Resource','Address','Addresses')) {
        $alias = Copy-Value $slot
        if ($null -ne $alias.PSObject.Properties[$reserved]) { $prior = $alias.$reserved; $alias.PSObject.Properties.Remove($reserved) }
        else { $prior = 'alias-marker' }
        $alias | Add-Member NoteProperty ($reserved.Substring(0,1).ToLowerInvariant() + $reserved.Substring(1)) $prior
        Assert ((Resolve-RemainingResourceRoutesJacket -Jacket $alias -Family $family).Failure()) "$name wrong-case $reserved accepted."; $passed++
    }
    $collision=[System.Collections.Hashtable]::new([StringComparer]::Ordinal)
    foreach ($property in $slot.PSObject.Properties) { $collision[$property.Name]=$property.Value }
    $collision['Address']='canonical-marker'; $collision['address']='alias-marker'
    Assert ((Resolve-RemainingResourceRoutesJacket -Jacket $collision -Family $family).Failure()) "$name case-colliding Address accepted."; $passed++
    $blank = Copy-Value $value; $blank.Addresses = @('') + @($blank.Addresses | Select-Object -Skip 1)
    Assert ((Resolve-RemainingResourceRoutesJacket -Jacket $blank -Family $family -ValidateNormalizedV2).Failure()) "$name blank hydrated route accepted."; $passed++
    if ($null -ne $field) {
        $orphan = Copy-Value $slot; $orphan.Routes[0].ResourceKey = 'orphan'
        Assert ((Resolve-RemainingResourceRoutesJacket -Jacket $orphan -Family $family).Failure()) "$name orphan ResourceKey accepted."; $passed++
        $arrayReference = Copy-Value $slot; $arrayReference.Routes[0].ResourceKey = @($key)
        Assert ((Resolve-RemainingResourceRoutesJacket -Jacket $arrayReference -Family $family).Failure()) "$name array ResourceKey accepted."; $passed++
        $arrayResourceKey = Copy-Value $slot; $arrayResourceKey.Resource[0].Key = @($key)
        Assert ((Resolve-RemainingResourceRoutesJacket -Jacket $arrayResourceKey -Family $family).Failure()) "$name array Resource Key accepted."; $passed++
        $missing = Copy-Value $value; $missing.Resource = ''
        Assert ((Resolve-RemainingResourceRoutesJacket -Jacket $missing -Family $family -ValidateNormalizedV2).Failure()) "$name blank hydrated resource accepted."; $passed++
    }
}
$sql = $slots | Where-Object Name -eq TestSqlDatabase | Select-Object -First 1
$badSql = Copy-Value $sql; $badSql.Resource[0].Database = 'Server=example;Database=x'
Assert ((Resolve-RemainingResourceRoutesJacket -Jacket $badSql -Family AzureSql).Failure()) 'Direct SQL v2 connection string accepted.'; $passed++
$preSql = Copy-Value $sql; $preSql.Resource[0].Database = '[Memory.SqlDatabase|]'
$pre = Resolve-RemainingResourceRoutesJacket -Jacket $preSql -Family AzureSql -AllowUnresolved
Assert ($pre.Success()) 'Deferred SQL v2 token rejected before hydration.'; $passed++
$hydratedSql = $pre.GetResult(); $hydratedSql.Resource = 'Server=example;Database=x'
Assert ((Resolve-RemainingResourceRoutesJacket -Jacket $hydratedSql -Family AzureSql -ValidateNormalizedV2).Failure()) 'Hydrated SQL v2 connection string accepted.'; $passed++
$v1Sql = [pscustomobject]@{ Resource = 'Data Source=example.database.windows.net;Initial Catalog=x;Authentication=Active Directory Default' }
Assert ((Resolve-RemainingResourceRoutesJacket -Jacket $v1Sql -Family AzureSql).Success()) 'V1 SQL connection string rejected.'; $passed++

# Exercise the actual loader seam with controlled manifest merge, hydration and Construct.
& (Get-Module SovereignTrust.Foundation) {
    $actualMerge=Invoke-MergeJson -Base ([pscustomobject]@{Addresses=@('manifest-head','manifest-tail')}) -Overlay ([pscustomobject]@{Addresses=@('source-head')}) -MergeArrayHandling Merge -MergeNullValueHandling Ignore -Depth 20 | Select-Object -Last 1
    if ($actualMerge.Failure() -or @($actualMerge.GetResult().Addresses).Count -ne 2) { throw 'Actual merge default-array behavior changed.' }
    $script:rrProbeType = $args[0]
    $script:rrMerge = [RemainingRRMerge]::new()
    $script:rrHydratedResource = 'resolved-resource'
    $script:rrHydratedAddress = 'https://resolved.example'
    function Resolve-DependencyModuleFromGraph {
        param($Signal,$ConductionContext,$WirePath)
        $s=[Signal]::Start('RRMockModule') | Select-Object -Last 1
        $s.SetResult($script:rrProbeType); return $s
    }
    function Resolve-PathFromDictionary {
        param($Dictionary,[string]$Path,$Default,$SignalLevel)
        $s=[Signal]::Start('RRMockPath') | Select-Object -Last 1
        switch ($Path) {
            '@.VirtualPath' { $s.SetResult($Dictionary.GetResult().VirtualPath) }
            '@.%.@.FullType' { $s.SetResult('RemainingRRProbe') }
            '@.%.@' { $s.SetResult([pscustomobject]@{ Addresses=@('manifest-default'); Resource='manifest-default' }) }
            '%.*.#.Adapters.*.#.MappedCondenser.@.$.*.#.MergeCondenser.@' { $s.SetResult($script:rrMerge) }
            default { throw "Unexpected loader path: $Path" }
        }
        return $s
    }
    function Add-PathToDictionary {
        param($Dictionary,[string]$Path,$Value)
        if ($Path -eq '@.Overlay') { $script:rrMerge.Overlay=$Value }
    }
    function Invoke-CondenserAdapter {
        param($Slot,$Activity,$Plan,$Signal,$ItemSignal)
        if ($script:rrHydrationFail) { return [Signal]::Start('RRHydrationFailure').LogCritical('Synthetic hydration failure.') }
        $j=$ItemSignal.GetJacket().GetResult()
        $j.Addresses=@($script:rrHydratedAddress) + @($j.Addresses | Select-Object -Skip 1)
        if ($null -ne $script:rrHydratedSecond -and $j.Addresses.Count -gt 1) { $j.Addresses[1] = $script:rrHydratedSecond }
        if ($null -ne $j.PSObject.Properties['Resource']) { $j.Resource=$script:rrHydratedResource }
        $s=[Signal]::Start('RRMockHydration') | Select-Object -Last 1
        $s.SetResult($j); return $s
    }
    function Invoke-LoaderCase($sourceValue) {
        $source=[Signal]::Start('RRSource') | Select-Object -Last 1
        $source.SetResult($sourceValue)
        $context=[Signal]::Start('RRContext') | Select-Object -Last 1
        return Resolve-AdapterFromJacket -Signal $context -ConductionContext $context -Jacket $source | Select-Object -Last 1
    }
    $v2=[pscustomobject]@{ VirtualPath='SovereignTrust.Adapters.Queue.AzureStorageQueue.Probe.Persistent.Read'; SchemaVersion=2; Resource=@([pscustomobject]@{Key='queue';QueuePath='[Memory.Queue|]' }); Routes=@([pscustomobject]@{Key='primary';Address='[Memory.Host|]';ResourceKey='queue'}) }
    $snapshot=$v2 | ConvertTo-Json -Depth 20 -Compress
    $ok=Invoke-LoaderCase $v2
    if ($ok.Failure() -or -not $ok.HasResult() -or $ok.GetResult().Jacket.Resource -cne 'resolved-resource' -or @($ok.GetResult().Jacket.Addresses)[0] -cne 'https://resolved.example' -or [RemainingRRProbe]::Count -ne 1) { throw "Loader selected queue v2 values did not reach Construct: failure=$($ok.Failure()) result=$($ok.HasResult()) count=$([RemainingRRProbe]::Count) message=$(@($ok.Entries.Message) -join ',')" }
    if (($v2 | ConvertTo-Json -Depth 20 -Compress) -cne $snapshot) { throw 'Loader mutated source v2.' }
    $count=[RemainingRRProbe]::Count
    $script:rrHydratedAddress=''
    $bad=Invoke-LoaderCase $v2
    if (-not $bad.Failure() -or $bad.HasResult() -or [RemainingRRProbe]::Count -ne $count) { throw 'Loader blank hydrated Address reached Construct.' }
    $script:rrHydratedAddress='https://resolved.example'; $script:rrHydratedResource=''
    $bad=Invoke-LoaderCase $v2
    if (-not $bad.Failure() -or $bad.HasResult() -or [RemainingRRProbe]::Count -ne $count) { throw 'Loader blank hydrated Resource reached Construct.' }
    $mixed=$v2 | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
    $mixed | Add-Member NoteProperty Addresses @('source-mixed')
    $mergeBefore=$script:rrMerge.Count
    $bad=Invoke-LoaderCase $mixed
    if (-not $bad.Failure() -or $script:rrMerge.Count -ne $mergeBefore -or [RemainingRRProbe]::Count -ne $count) { throw 'Loader source-mixed v2 reached merge or Construct.' }
    $script:rrMerge.Fail=$true
    $bad=Invoke-LoaderCase $v2
    if (-not $bad.Failure() -or $bad.HasResult() -or [RemainingRRProbe]::Count -ne $count) { throw 'Failed merge reached Construct.' }
    $script:rrMerge.Fail=$false
    $script:rrHydrationFail=$true
    $bad=Invoke-LoaderCase $v2
    if (-not $bad.Failure() -or $bad.HasResult() -or [RemainingRRProbe]::Count -ne $count) { throw 'Failed hydration reached Construct.' }
    $script:rrHydrationFail=$false
    $legacy=[pscustomobject]@{ VirtualPath=$v2.VirtualPath; Addresses=@('legacy-host'); Resource='legacy-resource' }
    $script:rrHydratedResource='legacy-resource'
    $old=Invoke-LoaderCase $legacy
    if ($old.Failure() -or -not $old.HasResult() -or [RemainingRRProbe]::Count -ne ($count+1)) { throw 'Loader v1 bypass changed.' }
    $slotFixtures=$args[1]
    foreach ($fixture in $slotFixtures) {
        $isConduction=$fixture.Name -eq 'ST_Conduction_ST'
        $isSql=$fixture.Name -eq 'TestSqlDatabase'
        if ($fixture.Name -in @('TestQueue','ST_Conduction_ST')) {
            $aliasFixture=$fixture | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
            $aliasFixture | Add-Member NoteProperty $(if ($isConduction) { 'resource' } else { 'address' }) '[Memory.SecretAlias|]'
            $priorMerge=$script:rrMerge.Count
            $priorConstruct=[RemainingRRProbe]::Count
            $aliasResult=Invoke-LoaderCase $aliasFixture
            if (-not $aliasResult.Failure() -or $aliasResult.HasResult() -or
                $script:rrMerge.Count -ne $priorMerge -or [RemainingRRProbe]::Count -ne $priorConstruct -or
                (@($aliasResult.Entries.Message) -join ',') -match 'SecretAlias') { throw "$($fixture.Name) reserved alias reached merge/Construct or leaked." }
        }
        $script:rrHydratedAddress=if ($isSql) { 'sql.database.windows.net' } else { 'https://resolved.example' }
        $script:rrHydratedSecond=if ($isConduction) { 'C:/modules' } else { $null }
        $script:rrHydratedResource=if ($isSql) { 'sda_fusion' } else { 'resolved-resource' }
        $before=[RemainingRRProbe]::Count
        $success=Invoke-LoaderCase $fixture
        if ($success.Failure() -or -not $success.HasResult() -or [RemainingRRProbe]::Count -ne ($before+1)) { throw "$($fixture.Name) loader v2 Construct failed." }
        $selected=$success.GetResult().Jacket
        $expectedCount=if ($isConduction) { 2 } else { 1 }
        if (@($selected.Addresses).Count -ne $expectedCount -or @($selected.Addresses)[0] -cne $script:rrHydratedAddress -or
            ($isConduction -and @($selected.Addresses)[1] -cne 'C:/modules') -or
            (-not $isConduction -and $selected.Resource -cne $script:rrHydratedResource)) { throw "$($fixture.Name) merged defaults replaced or augmented source selection." }
        $before=[RemainingRRProbe]::Count
        $script:rrHydratedAddress=''
        $bad=Invoke-LoaderCase $fixture
        if (-not $bad.Failure() -or $bad.HasResult() -or [RemainingRRProbe]::Count -ne $before) { throw "$($fixture.Name) blank Address reached Construct." }
        $script:rrHydratedAddress=if ($isSql) { 'sql.database.windows.net' } else { 'https://resolved.example' }
        if ($isConduction) { $script:rrHydratedSecond='' }
        else { $script:rrHydratedResource='' }
        $bad=Invoke-LoaderCase $fixture
        if (-not $bad.Failure() -or $bad.HasResult() -or [RemainingRRProbe]::Count -ne $before) { throw "$($fixture.Name) blank Resource/second root reached Construct." }
        $script:rrHydratedAddress='[Memory.UnresolvedSecret|]'
        if ($isConduction) { $script:rrHydratedSecond='C:/modules' }
        else { $script:rrHydratedResource=if ($isSql) { 'sda_fusion' } else { 'resolved-resource' } }
        $bad=Invoke-LoaderCase $fixture
        if (-not $bad.Failure() -or $bad.HasResult() -or [RemainingRRProbe]::Count -ne $before -or
            (@($bad.Entries.Message) -join ',') -match 'UnresolvedSecret') { throw "$($fixture.Name) unresolved Address reached Construct or leaked." }
        $script:rrHydratedAddress=if ($isSql) { 'sql.database.windows.net' } else { 'https://resolved.example' }
        if ($isConduction) { $script:rrHydratedSecond='[Memory.UnresolvedSecret|]' }
        else { $script:rrHydratedResource='[Memory.UnresolvedSecret|]' }
        $bad=Invoke-LoaderCase $fixture
        if (-not $bad.Failure() -or $bad.HasResult() -or [RemainingRRProbe]::Count -ne $before -or
            (@($bad.Entries.Message) -join ',') -match 'UnresolvedSecret') { throw "$($fixture.Name) unresolved Resource/second root reached Construct or leaked." }
        if ($isSql) {
            $script:rrHydratedResource='Server=evil;Database=x'
            $bad=Invoke-LoaderCase $fixture
            if (-not $bad.Failure() -or $bad.HasResult() -or [RemainingRRProbe]::Count -ne $before) { throw 'SQL token-produced connection string reached Construct.' }
        }
    }
} ([RemainingRRProbe]) @($slots | Where-Object { $_.Name -in @('Telemetry','TestQueue','Data-Media','TestSqlDatabase','TestADXDatabase','ST_Conduction_ST') })
$passed += 57
Write-Output "PASS $passed/$passed Remaining ResourceRoutes Foundation assertions"
