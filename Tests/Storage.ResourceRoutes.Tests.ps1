using module ../Src/PowerShell/SovereignTrust.Foundation.psd1
param([string]$ConfigPath)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Src/PowerShell/SovereignTrust.Foundation.psd1') -Force

class StorageRRProbe {
    static [int]$Count = 0
    [object]$Jacket
    [object] Construct([object]$jacket) {
        [StorageRRProbe]::Count++
        $this.Jacket = $jacket
        return & (Get-Module SovereignTrust.Foundation) {
            $signalType = 'Signal' -as [type]
            $signal = $signalType::Start('StorageRRProbe.Construct') | Select-Object -Last 1
            $signal.SetResult($true)
            return $signal
        }
    }
}
class StorageRRMerge {
    [int]$Count = 0
    [object]$Overlay
    [bool]$FailNext = $false
    [bool]$AppendTail = $false
    [object] Invoke([object]$slot,[object]$activity,[object]$signal,[object]$plan,[object]$itemSignal) {
        $this.Count++
        if ($this.FailNext) {
            $this.FailNext = $false
            return & (Get-Module SovereignTrust.Foundation) {
                $signalType = 'Signal' -as [type]
                $r = $signalType::Start('MockMergeFailure') | Select-Object -Last 1
                $r.LogCritical('Expected merge failure.') | Out-Null
                return $r
            }
        }
        $merged = $this.Overlay | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        if ($null -eq $merged.PSObject.Properties['Addresses']) { $merged | Add-Member NoteProperty Addresses @('manifest-default') }
        if ($this.AppendTail) { $merged.Addresses = @($merged.Addresses) + @('C:/manifest-tail') }
        return & (Get-Module SovereignTrust.Foundation) {
            $signalType = 'Signal' -as [type]
            $r = $signalType::Start('MockMerge') | Select-Object -Last 1
            $r.SetResult($args[0])
            return $r
        } $merged
    }
}

function Assert([bool]$condition, [string]$message) { if (-not $condition) { throw $message } }
$passes = 0
$root = Join-Path ([IO.Path]::GetTempPath()) ('st-rr-embedded-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
try {
    $v2 = [pscustomobject]@{ SchemaVersion = 2; Routes = @([pscustomobject]@{ Key = 'primary'; Address = $root }) }
    $source = $v2 | ConvertTo-Json -Depth 10 -Compress
    $converted = Resolve-StorageResourceRoutesJacket -Jacket $v2 -Family EmbeddedFileSystem
    Assert ($converted.Success() -and $converted.HasResult() -and @($converted.GetResult().Addresses)[0] -ceq $root) 'Embedded v2 route normalization failed.'
    Assert (($v2 | ConvertTo-Json -Depth 10 -Compress) -ceq $source) 'Embedded source jacket was changed.'
    $passes += 2

    $secondRoot = Join-Path $root 'fallback'
    New-Item -ItemType Directory -Path $secondRoot | Out-Null
    $ordered = [pscustomobject]@{ SchemaVersion = 2; Routes = @(
        [pscustomobject]@{ Key = 'primary'; Address = $root },
        [pscustomobject]@{ Key = 'fallback'; Address = $secondRoot }
    ) }
    $orderedSource = $ordered | ConvertTo-Json -Depth 10 -Compress
    $orderedResolution = Resolve-StorageResourceRoutesJacket -Jacket $ordered -Family EmbeddedFileSystem
    Assert ($orderedResolution.Success() -and @($orderedResolution.GetResult().Addresses).Count -eq 2 -and
        @($orderedResolution.GetResult().Addresses)[0] -ceq $root -and
        @($orderedResolution.GetResult().Addresses)[1] -ceq $secondRoot) 'Embedded ordered route normalization failed.'
    Assert (($ordered | ConvertTo-Json -Depth 10 -Compress) -ceq $orderedSource) 'Embedded ordered source changed.'
    Assert ((Resolve-StorageResourceRoutesJacket -Jacket $orderedResolution.GetResult() -Family EmbeddedFileSystem -ValidateNormalizedV2).Success()) 'Embedded hydrated second root was rejected.'
    $passes += 3

    foreach ($bad in @(
        [pscustomobject]@{ SchemaVersion=2; Routes=@([pscustomobject]@{Key='primary';Address=$root},[pscustomobject]@{Key='PRIMARY';Address=$secondRoot}) },
        [pscustomobject]@{ SchemaVersion=2; Routes=@([pscustomobject]@{Key='primary';Address=$root},[pscustomobject]@{Key=' ';Address=$secondRoot}) },
        [pscustomobject]@{ SchemaVersion=2; Routes=@([pscustomobject]@{Key='fallback';Address=$root},[pscustomobject]@{Key='primary';Address=$secondRoot}) },
        [pscustomobject]@{ SchemaVersion=2; Routes=@([pscustomobject]@{Key='primary';Address=$root},[pscustomobject]@{Key='fallback';Address=' '}) },
        [pscustomobject]@{ SchemaVersion=2; Routes=@([pscustomobject]@{Key='primary';Address=$root},[pscustomobject]@{Key='fallback';Address=$secondRoot;ResourceKey='orphan'}) },
        [pscustomobject]@{ SchemaVersion=2; Routes=@([pscustomobject]@{Key='primary';Address=$root},[pscustomobject]@{Key='fallback';Address=$secondRoot});Resource='bad' }
    )) {
        Assert ((Resolve-StorageResourceRoutesJacket -Jacket $bad -Family EmbeddedFileSystem).Failure()) 'Invalid second embedded route was admitted.'
        $passes++
    }
    foreach ($badRoot in @('', '[System.Unresolved|]')) {
        $badHydrated = [pscustomobject]@{ Addresses=@($root,$badRoot) }
        Assert ((Resolve-StorageResourceRoutesJacket -Jacket $badHydrated -Family EmbeddedFileSystem -ValidateNormalizedV2).Failure()) 'Invalid hydrated second root was admitted.'
        $passes++
    }
    Assert ((Resolve-StorageResourceRoutesJacket -Jacket $ordered -Family LocalFileSystem).Failure()) 'LocalFileSystem adopted multi-root v2.'
    $cloudMulti = [pscustomobject]@{SchemaVersion=2;Resource=@([pscustomobject]@{Key='container';Container='fixture'});Routes=@(
        [pscustomobject]@{Key='primary';Address='https://fixture.example/';ResourceKey='container'},
        [pscustomobject]@{Key='fallback';Address='https://fixture.example/';ResourceKey='container'})}
    Assert ((Resolve-StorageResourceRoutesJacket -Jacket $cloudMulti -Family AzureStorageAccount).Failure()) 'AzureStorageAccount adopted multi-root v2.'
    $passes += 2

    $unresolved = [pscustomobject]@{ SchemaVersion = 2; Routes = @([pscustomobject]@{ Key = 'primary'; Address = '[System.Path|]' }) }
    Assert ((Resolve-StorageResourceRoutesJacket -Jacket $unresolved -Family EmbeddedFileSystem).Failure()) 'Direct unresolved route was admitted.'
    $pre = Resolve-StorageResourceRoutesJacket -Jacket $unresolved -Family EmbeddedFileSystem -AllowUnresolved
    Assert ($pre.Success() -and $pre.HasResult()) 'Prehydration route was rejected.'
    Assert ((Resolve-StorageResourceRoutesJacket -Jacket $pre.GetResult() -Family EmbeddedFileSystem -ValidateNormalizedV2).Failure()) 'Hydration-success unresolved route was admitted.'
    $passes += 3

    foreach ($bad in @(
        [pscustomobject]@{ SchemaVersion = 2; Routes = @([pscustomobject]@{ Key = 'wrong'; Address = $root }) },
        [pscustomobject]@{ SchemaVersion = 2; Routes = @([pscustomobject]@{ Key = 'primary'; Address = '' }) },
        [pscustomobject]@{ SchemaVersion = 2; Routes = @([pscustomobject]@{ Key = 'primary'; Address = $root; ResourceKey = 'orphan' }) },
        [pscustomobject]@{ SchemaVersion = 2; Routes = @([pscustomobject]@{ Key = 'primary'; Address = $root; ApiKind = $null }) },
        [pscustomobject]@{ SchemaVersion = 2; Routes = @([pscustomobject]@{ Key = 'primary'; Address = $root }); Addresses = @($root) },
        [pscustomobject]@{ SchemaVersion = 2; Routes = @([pscustomobject]@{ Key = 'primary'; Address = $root },[pscustomobject]@{ Key = 'primary'; Address = $root }) }
    )) {
        Assert ((Resolve-StorageResourceRoutesJacket -Jacket $bad -Family EmbeddedFileSystem).Failure()) 'Malformed embedded v2 route was admitted.'
        $passes++
    }
    $legacy = [pscustomobject]@{ Addresses = @($root, 'fallback') }
    $legacyResult = Resolve-StorageResourceRoutesJacket -Jacket $legacy -Family EmbeddedFileSystem
    Assert ($legacyResult.Success() -and @($legacyResult.GetResult().Addresses).Count -eq 2) 'Legacy addresses changed.'
    $passes++

    $vaultV2 = [pscustomobject]@{ SchemaVersion=2; Resource=@([pscustomobject]@{Key='vault';Vault='vault'}); Routes=@([pscustomobject]@{Key='primary';Address='https://vault.vault.azure.net/';ResourceKey='vault'}) }
    $vaultResolved = Resolve-StorageResourceRoutesJacket -Jacket $vaultV2 -Family AzureKeyVault
    Assert ($vaultResolved.Success() -and $vaultResolved.GetResult().Resource -ceq 'vault' -and @($vaultResolved.GetResult().Addresses)[0] -ceq 'https://vault.vault.azure.net/') 'Direct KeyVault v2 route failed.'
    $passes++
    foreach ($bad in @(
        [pscustomobject]@{SchemaVersion=2;Resource=@([pscustomobject]@{Key='vault';Vault='other'});Routes=@([pscustomobject]@{Key='primary';Address='https://vault.vault.azure.net/';ResourceKey='vault'})},
        [pscustomobject]@{SchemaVersion=2;Resource=@([pscustomobject]@{Key='vault';Vault='vault'});Routes=@([pscustomobject]@{Key='primary';Address='https://vault.vault.azure.net/';ResourceKey='missing'})},
        [pscustomobject]@{SchemaVersion=2;Resource=@([pscustomobject]@{Key='vault';Vault='vault'});Routes=@([pscustomobject]@{Key='primary';Address='https://vault.vault.azure.net/';ResourceKey='vault';ApiKind='extra'})},
        [pscustomobject]@{SchemaVersion=2;Resource=@([pscustomobject]@{Key='vault';Vault='vault';Credentials='extra'});Routes=@([pscustomobject]@{Key='primary';Address='https://vault.vault.azure.net/';ResourceKey='vault'})},
        [pscustomobject]@{SchemaVersion=2;Resource=@([pscustomobject]@{Key='vault';Vault='vault'});Routes=@([pscustomobject]@{Key='primary';Address='https://vault.vault.azure.net/';ResourceKey='vault'},[pscustomobject]@{Key='primary';Address='https://vault.vault.azure.net/';ResourceKey='vault'})},
        [pscustomobject]@{SchemaVersion=2;Resource=@([pscustomobject]@{Key='vault';Vault='vault'});Routes=@([pscustomobject]@{Key='primary';Address='https://vault.vault.azure.net/';ResourceKey='vault'});Addresses=@('legacy')}
    )) {
        Assert ((Resolve-StorageResourceRoutesJacket -Jacket $bad -Family AzureKeyVault).Failure()) 'Malformed direct KeyVault v2 was admitted.'
        $passes++
    }
    $vaultV1 = [pscustomobject]@{Addresses=@('https://vault.vault.azure.net/');Resource='legacy-id'}
    Assert ((Resolve-StorageResourceRoutesJacket -Jacket $vaultV1 -Family AzureKeyVault).GetResult().Resource -ceq 'legacy-id') 'Direct KeyVault v1 pass-through changed.'
    $passes++

    $module = Get-Module SovereignTrust.Foundation
    & $module {
        $adapter = [Storage_EmbeddedFileSystem]::new()
        $construct = $adapter.Construct($args[0])
        if ($construct.Failure()) { throw 'Embedded direct v2 Construct failed.' }
        $signal = [Signal]::Start('EmbeddedRR') | Select-Object -Last 1
        $write = $adapter.Invoke('LocalContent', 'Write', $signal, [pscustomobject]@{ VirtualPath = 'sample.txt'; Config = [pscustomobject]@{ Content = 'route-content' } }, $signal)
        if ($write.Failure()) { throw 'Embedded direct v2 Write failed.' }
        $exists = $adapter.Invoke('LocalContent', 'Exists', $signal, [pscustomobject]@{ VirtualPath = 'sample.txt'; Config = [pscustomobject]@{} }, $signal)
        if ($exists.Failure() -or $exists.GetResult() -ne $true) { throw 'Embedded direct v2 Exists failed.' }
        $read = $adapter.Invoke('LocalContent', 'Read', $signal, [pscustomobject]@{ VirtualPath = 'sample.txt'; Config = [pscustomobject]@{} }, $signal)
        if ($read.Failure() -or $read.GetResult() -cne 'route-content') { throw 'Embedded direct v2 Read failed.' }
        $deleted = $adapter.Invoke('LocalContent', 'Delete', $signal, [pscustomobject]@{ VirtualPath = 'sample.txt'; Config = [pscustomobject]@{} }, $signal)
        if ($deleted.Failure() -or (Test-Path -LiteralPath (Join-Path $args[1] 'sample.txt'))) { throw 'Embedded direct v2 Delete failed.' }
        $legacy = [Storage_EmbeddedFileSystem]::new()
        if ($legacy.Construct([pscustomobject]@{ Addresses = @($args[1]) }).Failure()) { throw 'Embedded direct v1 Construct failed.' }
        $writeV1 = $legacy.Invoke('LocalContent', 'Write', $signal, [pscustomobject]@{ VirtualPath = 'sample.txt'; Config = [pscustomobject]@{ Content = 'route-content' } }, $signal)
        $readV1 = $legacy.Invoke('LocalContent', 'Read', $signal, [pscustomobject]@{ VirtualPath = 'sample.txt'; Config = [pscustomobject]@{} }, $signal)
        $existsV1 = $legacy.Invoke('LocalContent', 'Exists', $signal, [pscustomobject]@{ VirtualPath = 'sample.txt'; Config = [pscustomobject]@{} }, $signal)
        $deleteV1 = $legacy.Invoke('LocalContent', 'Delete', $signal, [pscustomobject]@{ VirtualPath = 'sample.txt'; Config = [pscustomobject]@{} }, $signal)
        if ($writeV1.Failure() -or $readV1.Failure() -or $readV1.GetResult() -cne 'route-content' -or $existsV1.GetResult() -ne $true -or $deleteV1.Failure()) { throw 'Embedded v1/v2 operation parity failed.' }
    } $v2 $root
    Assert (-not (Test-Path -LiteralPath (Join-Path $root 'sample.txt'))) 'Embedded delete left file.'
    $passes += 9

    [IO.File]::WriteAllText((Join-Path $secondRoot 'both.txt'), 'fallback-both')
    [IO.File]::WriteAllText((Join-Path $root 'both.txt'), 'primary-both')
    [IO.File]::WriteAllText((Join-Path $secondRoot 'fallback.txt'), 'fallback-only')
    & $module {
        $roots = $args[0]
        $adapter = [Storage_EmbeddedFileSystem]::new()
        if ($adapter.Construct($roots).Failure()) { throw 'Two-root direct Construct failed.' }
        $signal = [Signal]::Start('TwoRootDirect') | Select-Object -Last 1
        function Call($activity,$name,$content) {
            $plan = [pscustomobject]@{VirtualPath=$name;Config=[pscustomobject]@{Content=$content}}
            return $adapter.Invoke('LocalContent',$activity,$signal,$plan,$signal) | Select-Object -Last 1
        }
        if ((Call Read both.txt $null).GetResult() -cne 'primary-both') { throw 'Two-root Read did not prefer primary.' }
        if ((Call Read fallback.txt $null).GetResult() -cne 'fallback-only') { throw 'Two-root Read did not fall back.' }
        if (-not (Call Read missing.txt $null).Failure()) { throw 'Two-root missing Read unexpectedly succeeded.' }
        if ((Call Exists both.txt $null).GetResult() -ne $true -or
            (Call Exists fallback.txt $null).GetResult() -ne $true -or
            (Call Exists missing.txt $null).GetResult() -ne $false) { throw 'Two-root Exists selection failed.' }
        if ((Call Write both.txt overwritten).Failure() -or (Call Delete both.txt $null).Failure()) { throw 'Two-root primary Write/Delete failed.' }
        if ((Call Delete fallback.txt $null).Failure()) { throw 'Two-root Delete with missing primary failed.' }
    } $ordered
    Assert (-not (Test-Path -LiteralPath (Join-Path $root 'both.txt')) -and
        [IO.File]::ReadAllText((Join-Path $secondRoot 'both.txt')) -ceq 'fallback-both' -and
        [IO.File]::ReadAllText((Join-Path $secondRoot 'fallback.txt')) -ceq 'fallback-only') 'Two-root Write/Delete touched fallback.'
    $passes += 8

    # Isolate the real Resolve-AdapterFromJacket seam with provider-free merge/hydration stubs.
    & $module {
        $script:probeType = $args[0]
        $script:hydrationMode = 'resolved'
        $script:hydrationCount = 0
        $script:expectedRoots = @($args[1],$args[2])
        $script:mergeService = [StorageRRMerge]::new()
        function Resolve-DependencyModuleFromGraph {
            param($Signal,$ConductionContext,$WirePath)
            $r = [Signal]::Start('MockModule') | Select-Object -Last 1
            $r.SetResult($script:probeType)
            return $r
        }
        function Resolve-PathFromDictionary {
            param($Dictionary,[string]$Path,$Default,$SignalLevel)
            $r = [Signal]::Start('MockPath') | Select-Object -Last 1
            switch ($Path) {
                '@.VirtualPath' { $r.SetResult($Dictionary.GetResult().VirtualPath) }
                '@.%.@.FullType' { $r.SetResult('StorageRRProbe') }
                '@.%.@' { $r.SetResult([pscustomobject]@{ Addresses = @('manifest-default') }) }
                '%.*.#.Adapters.*.#.MappedCondenser.@.$.*.#.MergeCondenser.@' { $r.SetResult($script:mergeService) }
                default { throw "Unexpected loader path: $Path" }
            }
            return $r
        }
        function Add-PathToDictionary {
            param($Dictionary,[string]$Path,$Value)
            if ($Path -eq '@.Overlay') { $script:mergeService.Overlay = $Value }
        }
        function Invoke-CondenserAdapter {
            param($Slot,$Activity,$Plan,$Signal,$ItemSignal)
            $script:hydrationCount++
            $jacket = $ItemSignal.GetJacket().GetResult()
            $vaultCase = [string]$jacket.VirtualPath -match '\.AzureKeyVault\.'
            $goodAddress = if ($vaultCase) { 'https://vault.vault.azure.net/' } else { 'C:/hydrated-root' }
            $goodResource = if ($vaultCase) { 'vault' } else { 'hydrated-box' }
            if ($script:hydrationMode -eq 'multi') {
                if (@($jacket.Addresses).Count -ne 2 -or
                    @($jacket.Addresses)[0] -cne '[System.PrimaryRoot|]' -or
                    @($jacket.Addresses)[1] -cne '[System.FallbackRoot|]') { throw 'Manifest tail reached hydration or source root order changed.' }
                $jacket.Addresses = @($script:expectedRoots)
            }
            elseif ($script:hydrationMode -eq 'bad-second') { $jacket.Addresses = @($script:expectedRoots[0], '[System.UnresolvedSecond|]') }
            elseif ($script:hydrationMode -eq 'resolved') {
                $jacket.Addresses = @($goodAddress)
                if ($null -ne $jacket.PSObject.Properties['Resource']) { $jacket.Resource = $goodResource }
            }
            elseif ($script:hydrationMode -eq 'blank') { $jacket.Addresses = @('') }
            elseif ($script:hydrationMode -eq 'container-blank') { $jacket.Addresses = @($goodAddress); $jacket.Resource = '' }
            elseif ($script:hydrationMode -eq 'container-unresolved') { $jacket.Addresses = @($goodAddress) }
            $r = [Signal]::Start('MockHydration') | Select-Object -Last 1
            $r.SetResult($jacket)
            return $r
        }
        function Invoke-Case($address,[string]$mode,[bool]$mixed,[string]$family = 'EmbeddedFileSystem',[bool]$legacy = $false) {
            $script:hydrationMode = $mode
            $input = if ($legacy) {
                [pscustomobject]@{ VirtualPath = "SovereignTrust.Adapters.Storage.$family.Probe.Persistent.Read"; Addresses = @($address) }
            } else {
                $routeList = if ($address -is [array]) { @([pscustomobject]@{Key='primary';Address=$address[0]},[pscustomobject]@{Key='fallback';Address=$address[1]}) } else { @([pscustomobject]@{Key='primary';Address=$address}) }
                [pscustomobject]@{ VirtualPath = "SovereignTrust.Adapters.Storage.$family.Probe.Persistent.Read"; SchemaVersion = 2; Routes = @($routeList) }
            }
            if ($family -eq 'AzureStorageAccount') {
                if ($legacy) { $input | Add-Member NoteProperty Resource '[Memory.SecretContainer|]' }
                else {
                    $input.Routes[0] | Add-Member NoteProperty ResourceKey 'container'
                    $input | Add-Member NoteProperty Resource @([pscustomobject]@{ Key = 'container'; Container = '[Memory.SecretContainer|]' })
                }
            }
            if ($family -eq 'AzureKeyVault' -and -not $legacy) {
                $input.Routes[0] | Add-Member NoteProperty ResourceKey 'vault'
                $input | Add-Member NoteProperty Resource @([pscustomobject]@{ Key = 'vault'; Vault = $(if ($mode -eq 'container-unresolved') { '[Memory.SecretVault|]' } else { 'vault' }) })
            }
            if ($mixed) { $input | Add-Member NoteProperty Addresses @('source-mixed') }
            $sourceJson = $input | ConvertTo-Json -Depth 20 -Compress
            $source = [Signal]::Start('SourceStorage') | Select-Object -Last 1
            $source.SetResult($input)
            $context = [Signal]::Start('Context') | Select-Object -Last 1
            $result = Resolve-AdapterFromJacket -Signal $context -ConductionContext $context -Jacket $source | Select-Object -Last 1
            if (($input | ConvertTo-Json -Depth 20 -Compress) -cne $sourceJson) { throw 'Loader mutated source jacket.' }
            return $result
        }
        $positive = Invoke-Case '[System.Root|]' 'resolved' $false
        if ($positive.Failure() -or -not $positive.HasResult() -or @($positive.GetResult().Jacket.Addresses)[0] -cne 'C:/hydrated-root') { throw "Loader v2 merge/hydration/Construct parity failed: failure=$($positive.Failure()) result=$($positive.HasResult()) messages=$(@($positive.Entries.Message) -join ',')" }
        $script:mergeService.AppendTail = $true
        $multi = Invoke-Case @('[System.PrimaryRoot|]','[System.FallbackRoot|]') 'multi' $false
        if ($multi.Failure() -or -not $multi.HasResult() -or
            @($multi.GetResult().Jacket.Addresses).Count -ne 2 -or
            @($multi.GetResult().Jacket.Addresses)[0] -cne $script:expectedRoots[0] -or
            @($multi.GetResult().Jacket.Addresses)[1] -cne $script:expectedRoots[1]) { throw 'Embedded loader failed to discard manifest tail and retain two hydrated roots.' }
        $script:mergeService.AppendTail = $false
        $beforeBadSecond = [StorageRRProbe]::Count
        $badSecond = Invoke-Case @('[System.PrimaryRoot|]','[System.FallbackRoot|]') 'bad-second' $false
        if (-not $badSecond.Failure() -or $badSecond.HasResult() -or [StorageRRProbe]::Count -ne $beforeBadSecond) { throw 'Unresolved second loader root reached Construct.' }
        $beforeMergeHydration = $script:hydrationCount
        $script:mergeService.FailNext = $true
        $mergeFailed = Invoke-Case @('[System.PrimaryRoot|]','[System.FallbackRoot|]') 'multi' $false
        if (-not $mergeFailed.Failure() -or $mergeFailed.HasResult() -or
            [StorageRRProbe]::Count -ne $beforeBadSecond -or $script:hydrationCount -ne $beforeMergeHydration) { throw 'Failed embedded v2 merge reached hydration or Construct.' }
        $count = [StorageRRProbe]::Count
        foreach ($mode in @('unresolved','blank')) {
            $bad = Invoke-Case '[System.SecretRoot|]' $mode $false
            if (-not $bad.Failure() -or $bad.HasResult() -or [StorageRRProbe]::Count -ne $count -or (@($bad.Entries.Message) -join ',') -match 'SecretRoot') { throw "Loader admitted or leaked $mode hydrated v2 route." }
        }
        $azurePositive = Invoke-Case '[System.SecretRoot|]' 'resolved' $false 'AzureStorageAccount'
        if ($azurePositive.Failure() -or $azurePositive.GetResult().Jacket.Resource -cne 'hydrated-box') { throw 'Loader Azure v2 Container hydration failed.' }
        $count = [StorageRRProbe]::Count
        foreach ($mode in @('container-unresolved','container-blank')) {
            $bad = Invoke-Case '[System.SecretRoot|]' $mode $false 'AzureStorageAccount'
            if (-not $bad.Failure() -or $bad.HasResult() -or [StorageRRProbe]::Count -ne $count -or (@($bad.Entries.Message) -join ',') -match 'SecretContainer') { throw "Loader admitted or leaked $mode hydrated v2 Container." }
        }
        $vaultPositive = Invoke-Case '[System.SecretRoot|]' 'resolved' $false 'AzureKeyVault'
        if ($vaultPositive.Failure() -or $vaultPositive.GetResult().Jacket.Resource -cne 'vault' -or @($vaultPositive.GetResult().Jacket.Addresses)[0] -cne 'https://vault.vault.azure.net/') { throw 'Loader KeyVault v2 hydration failed.' }
        $count = [StorageRRProbe]::Count
        foreach ($mode in @('unresolved','blank','container-unresolved','container-blank')) {
            $bad = Invoke-Case '[System.SecretRoot|]' $mode $false 'AzureKeyVault'
            if (-not $bad.Failure() -or $bad.HasResult() -or [StorageRRProbe]::Count -ne $count -or (@($bad.Entries.Message) -join ',') -match 'SecretRoot|SecretVault') { throw "Loader admitted or leaked $mode hydrated v2 Vault route." }
        }
        $vaultMergeBefore = $script:mergeService.Count
        $mixedVault = Invoke-Case '[System.SecretRoot|]' 'resolved' $true 'AzureKeyVault'
        if (-not $mixedVault.Failure() -or $script:mergeService.Count -ne $vaultMergeBefore -or [StorageRRProbe]::Count -ne $count) { throw 'Mixed KeyVault v2 reached merge or Construct.' }
        $legacyVault = Invoke-Case 'https://vault.vault.azure.net/' 'unresolved' $false 'AzureKeyVault' $true
        if ($legacyVault.Failure() -or -not $legacyVault.HasResult() -or [StorageRRProbe]::Count -ne ($count+1)) { throw 'Loader KeyVault real-v1 bypass changed.' }
        $count = [StorageRRProbe]::Count
        $legacy = Invoke-Case 'C:/legacy-root' 'unresolved' $false 'EmbeddedFileSystem' $true
        if ($legacy.Failure() -or -not $legacy.HasResult() -or [StorageRRProbe]::Count -ne ($count+1)) { throw 'Loader v1 bypass changed.' }
        $mergeBefore = $script:mergeService.Count
        $mixed = Invoke-Case '[System.Root|]' 'resolved' $true
        if (-not $mixed.Failure() -or $script:mergeService.Count -ne $mergeBefore) { throw 'Source-mixed v2 reached merge.' }
    } ([StorageRRProbe]) $root $secondRoot
    $passes += 20

    [IO.File]::WriteAllText((Join-Path $root 'ProbeModule.psm1'), '# fixture')
    & $module {
        $script:rootPath = $args[0]
        $script:rootAdapter = [Storage_EmbeddedFileSystem]::new()
        $rootJacket = [pscustomobject]@{ SchemaVersion = 2; Routes = @([pscustomobject]@{ Key = 'primary'; Address = $script:rootPath }) }
        if ($script:rootAdapter.Construct($rootJacket).Failure()) { throw 'ModuleRoots direct v2 construction failed.' }
        $mapped = [MappedStorageAdapter]::new()
        $mapped.Signal = [Signal]::Start('MappedRR') | Select-Object -Last 1
        $script:observedVirtualPath = $null
        $script:provider = [pscustomobject]@{}
        $script:provider | Add-Member ScriptMethod Invoke {
            param($slot,$activity,$signal,$plan,$itemSignal)
            $script:observedVirtualPath = $plan.VirtualPath
            $r = [Signal]::Start('MappedProviderMock') | Select-Object -Last 1
            $r.SetResult('mapped-result')
            return $r
        }
        function Resolve-PathFromDictionary {
            param($Dictionary,[string]$Path,$Default,$SignalLevel)
            $r = [Signal]::Start('StorageRouteFixture') | Select-Object -Last 1
            switch -Wildcard ($Path) {
                '$.*.#.ModuleRoots' { $r.SetResult($script:rootAdapter) }
                '$.*.#.LocalContent' { $r.SetResult($script:provider) }
                '*.#.LocalContent' { $r.SetResult($script:provider) }
                '$.%.@.Addresses' { $r.SetResult(@($script:rootPath)) }
                'Config.VirtualPath' { }
                'Resource' { $r.SetResult('file.txt') }
                'Container' { $r.SetResult('bucket') }
                default { throw "Unexpected mapped/module path: $Path" }
            }
            return $r
        }
        function Resolve-MappedAdapter {
            param($AdapterSignal,$Signal,$ConductionContext)
            $r = [Signal]::Start('ResolvedStorageFixture') | Select-Object -Last 1
            $r.SetResult($AdapterSignal.GetResult())
            return $r
        }
        function Add-PathToDictionary {
            param($Dictionary,[string]$Path,$Value)
            if ($Path -eq 'VirtualPath') { $Dictionary | Add-Member -Force NoteProperty VirtualPath $Value }
        }
        $context = [Signal]::Start('ModuleContext') | Select-Object -Last 1
        $resolved = Resolve-ModulePathFromAdapter -Adapter $mapped -Signal $context -Slot ModuleRoots -RelativePath ProbeModule.psm1 | Select-Object -Last 1
        if ($resolved.Failure() -or -not $resolved.HasResult() -or $resolved.GetResult() -cne (Join-Path $script:rootPath 'ProbeModule.psm1')) { throw 'ModuleRoots actual resolution failed.' }
        $plan = [pscustomobject]@{ Container = 'bucket'; Resource = 'file.txt'; Config = [pscustomobject]@{} }
        $invoked = $mapped.Invoke('LocalContent','Read',$context,$plan,$context) | Select-Object -Last 1
        if ($invoked.Failure() -or $script:observedVirtualPath -cne 'bucket/file.txt') { throw 'Mapped Container/Resource virtual path synthesis changed.' }
    } $root
    $passes += 2

    [IO.File]::WriteAllText((Join-Path $secondRoot 'LazyFixture.psm1'), '# second')
    & $module {
        $script:lazyRoots = @($args[0],$args[1])
        $script:lazyMode = 'good'
        $script:lazyHydrations = 0
        $script:lazyMerge = [StorageRRMerge]::new()
        $script:lazyMerge.AppendTail = $true
        $script:lazyReceiver = [pscustomobject]@{ Registration = $null }
        $script:lazyReceiver | Add-Member ScriptMethod RegisterAdapter {
            param($adapter,$slot)
            $this.Registration = $adapter
            $r = [Signal]::Start('LazyReceiver') | Select-Object -Last 1
            $r.SetResult($adapter)
            return $r
        }
        function Resolve-DependencyModuleFromGraph {
            param($Signal,$ConductionContext,$WirePath)
            $r = [Signal]::Start('LazyGraph') | Select-Object -Last 1
            $r.SetResult([StorageRRProbe])
            return $r
        }
        function Resolve-PathFromDictionary {
            param($Dictionary,[string]$Path,$Default,$SignalLevel)
            $r = [Signal]::Start('LazyPath') | Select-Object -Last 1
            switch ($Path) {
                'Adapters' { $r.SetResult($Dictionary.Adapters) }
                'AdapterJackets' { $r.SetResult($Dictionary.AdapterJackets) }
                'Name' { $r.SetResult($Dictionary.GetResult().Name) }
                '$.%.@.Kind' { $r.SetResult('Storage') }
                '$.%.@.Slot' { $r.SetResult('ModuleRoots') }
                '@.VirtualPath' { $r.SetResult($Dictionary.GetResult().VirtualPath) }
                '@.%.@.FullType' { $r.SetResult('StorageRRProbe') }
                '@.%.@' { $r.SetResult([pscustomobject]@{Addresses=@('manifest-default')}) }
                '%.*.#.Adapters.*.#.MappedCondenser.@.$.*.#.MergeCondenser.@' { $r.SetResult($script:lazyMerge) }
                '*.#.Adapters.*.#.MappedStorage' { $r.SetResult($script:lazyReceiver) }
                '$.*.#.ModuleRoots' {
                    $adapterSignal = [Signal]::Start('LazyRegisteredSlot') | Select-Object -Last 1
                    $adapterSignal.SetResult($script:lazyReceiver.Registration)
                    $r.SetResult($adapterSignal)
                }
                '$.%.@.Addresses' { $r.SetResult(@($Dictionary.Jacket.Addresses)) }
                default { throw "Unexpected lazy path: $Path" }
            }
            return $r
        }
        function Add-PathToDictionary {
            param($Dictionary,[string]$Path,$Value)
            if ($Path -eq '@.Overlay') { $script:lazyMerge.Overlay = $Value }
        }
        function Invoke-CondenserAdapter {
            param($Slot,$Activity,$Plan,$Signal,$ItemSignal)
            $script:lazyHydrations++
            $jacket = $ItemSignal.GetJacket().GetResult()
            if (@($jacket.Addresses).Count -ne 2 -or
                @($jacket.Addresses)[0] -cne '[System.PrimaryRoot|]' -or
                @($jacket.Addresses)[1] -cne '[System.FallbackRoot|]') { throw 'Lazy hydration did not receive exact source roots.' }
            if ($script:lazyMode -eq 'bad-second') { $jacket.Addresses = @($script:lazyRoots[0],'[System.UnresolvedSecond|]') }
            else { $jacket.Addresses = @($script:lazyRoots) }
            $r = [Signal]::Start('LazyHydration') | Select-Object -Last 1
            $r.SetResult($jacket)
            return $r
        }
        function New-Case {
            $jacketValue = [pscustomobject]@{Name='Modules';VirtualPath='SovereignTrust.Adapters.Storage.EmbeddedFileSystem.ModuleRoots.Persistent.Read';SchemaVersion=2;Routes=@(
                [pscustomobject]@{Key='primary';Address='[System.PrimaryRoot|]'},
                [pscustomobject]@{Key='fallback';Address='[System.FallbackRoot|]'}
            )}
            $jacket = [Signal]::Start('LazySource') | Select-Object -Last 1
            $jacket.SetResult($jacketValue)
            $conductor = [pscustomobject]@{Adapters=@{};AdapterJackets=@($jacket);Signal=$null}
            $conductor.Signal = [Signal]::Start('LazyConductor') | Select-Object -Last 1
            $conductor.Signal.SetResult($conductor)
            $context = [Signal]::Start('LazyContext') | Select-Object -Last 1
            $bootstrap = Resolve-ConductorAdapters -Signal $context -Conductor $conductor -UseLazyLoading | Select-Object -Last 1
            if ($bootstrap.Failure() -or -not $script:lazyReceiver.Registration.IsAdapterRegistration -or
                [StorageRRProbe]::Count -ne $script:beforeLazyConstruct) { throw 'Actual bootstrap did not register lazily.' }
            return $context
        }
        $mapped = [MappedStorageAdapter]::new()
        $script:beforeLazyConstruct = [StorageRRProbe]::Count
        $context = New-Case
        $first = Resolve-ModulePathFromAdapter -Adapter $mapped -Signal $context -Slot ModuleRoots -RelativePath LazyFixture.psm1 | Select-Object -Last 1
        if ($first.Failure() -or $first.GetResult() -cne (Join-Path $script:lazyRoots[1] 'LazyFixture.psm1') -or
            [StorageRRProbe]::Count -ne ($script:beforeLazyConstruct+1) -or
            @($script:lazyReceiver.Registration.Instance.Jacket.Addresses).Count -ne 2) { throw 'Actual lazy module fallback/Construct failed.' }
        $cached = $script:lazyReceiver.Registration.Instance
        $again = Resolve-ModulePathFromAdapter -Adapter $mapped -Signal $context -Slot ModuleRoots -RelativePath LazyFixture.psm1 | Select-Object -Last 1
        if ($again.Failure() -or [StorageRRProbe]::Count -ne ($script:beforeLazyConstruct+1) -or
            -not [object]::ReferenceEquals($cached,$script:lazyReceiver.Registration.Instance)) { throw 'Actual lazy lookup failed to reuse cached instance.' }
        [IO.File]::WriteAllText((Join-Path $script:lazyRoots[0] 'LazyFixture.psm1'), '# first')
        $primary = Resolve-ModulePathFromAdapter -Adapter $mapped -Signal $context -Slot ModuleRoots -RelativePath LazyFixture.psm1 | Select-Object -Last 1
        if ($primary.GetResult() -cne (Join-Path $script:lazyRoots[0] 'LazyFixture.psm1')) { throw 'Actual cached module lookup did not prefer primary.' }
        $missing = Resolve-ModulePathFromAdapter -Adapter $mapped -Signal $context -Slot ModuleRoots -RelativePath MissingFixture.psm1 | Select-Object -Last 1
        if (-not $missing.Failure() -or $missing.HasResult()) { throw 'Actual cached module lookup returned a missing path.' }
        $script:lazyReceiver.Registration = $null
        $script:lazyMode = 'bad-second'
        $script:beforeLazyConstruct = [StorageRRProbe]::Count
        $context = New-Case
        $failed = Resolve-ModulePathFromAdapter -Adapter $mapped -Signal $context -Slot ModuleRoots -RelativePath LazyFixture.psm1 | Select-Object -Last 1
        if (-not $failed.Failure() -or $failed.HasResult() -or $script:lazyReceiver.Registration.State -ne 'Failed' -or
            $null -ne $script:lazyReceiver.Registration.Instance -or [StorageRRProbe]::Count -ne $script:beforeLazyConstruct) { throw 'Failed lazy second hydration was cached or returned a module path.' }
        $script:lazyReceiver.Registration = $null
        $script:lazyMode = 'good'
        $script:beforeLazyConstruct = [StorageRRProbe]::Count
        $context = New-Case
        $script:lazyMerge.FailNext = $true
        $beforeHydrations = $script:lazyHydrations
        $failedMerge = Resolve-ModulePathFromAdapter -Adapter $mapped -Signal $context -Slot ModuleRoots -RelativePath LazyFixture.psm1 | Select-Object -Last 1
        if (-not $failedMerge.Failure() -or $failedMerge.HasResult() -or $script:lazyReceiver.Registration.State -ne 'Failed' -or
            $script:lazyHydrations -ne $beforeHydrations -or [StorageRRProbe]::Count -ne $script:beforeLazyConstruct) { throw 'Failed lazy merge reached hydration/Construct or returned path.' }
    } $root $secondRoot
    $passes += 7

    if ($ConfigPath) {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -Depth 100
        if (@($config.Agents).Count -eq 1 -and $config.Agents[0].Roles -is [array]) {
            $slots = @($config.Agents[0].Roles[0].Adapters)
            Assert ($slots.Count -eq 21) 'Config adapter inventory changed.'
            foreach ($name in @('Modules','RemoteMedia','RemoteContent','LocalContent','LocalMedia','LocalMeta','Meta','LocalResources')) {
                $slot = $slots | Where-Object Name -CEQ $name | Select-Object -First 1
                Assert ($slot.SchemaVersion -eq 2 -and @($slot.Routes).Count -eq 1 -and $slot.Routes[0].Key -ceq 'primary') "Config Storage route invalid: $name"
                $passes++
            }
            $passes++
        }
        elseif (@($config.Agents).Count -eq 2 -and
            @($config.Agents | ForEach-Object Name) -join ',' -ceq 'sdadev01,sdadev02') {
            $entries = @(
                foreach ($agent in $config.Agents) {
                    foreach ($roleProperty in $agent.Roles.PSObject.Properties) {
                        foreach ($adapter in @($roleProperty.Value.Adapters)) {
                            [pscustomobject]@{Agent=$agent.Name;Role=$roleProperty.Name;Adapter=$adapter}
                        }
                    }
                }
            )
            Assert ($entries.Count -eq 40) 'SDAFusion adapter inventory changed.'
            $passes++
            $expected = @(
                [pscustomobject]@{Agent='sdadev01';Role='SDAWorkItems';Index=0;Name='Modules';Addresses=@('[Formatter.FilePath.[System.STSourceRoot/]/]','[Formatter.FilePath.[System.STProgramFiles/].PowerShell.Modules/]')},
                [pscustomobject]@{Agent='sdadev01';Role='DiscordRelay';Index=0;Name='Modules';Addresses=@('[Formatter.FilePath.[System.STSourceRoot/]/]','[Formatter.FilePath.[System.STProgramFiles/].PowerShell.Modules/]')},
                [pscustomobject]@{Agent='sdadev02';Role='Bond';Index=0;Name='IgnoreModules';Addresses=@('C.GitHub.SiliconDreamArtists','C.Program Files.PowerShell.Modules')}
            )
            foreach ($spec in $expected) {
                $agent = $config.Agents | Where-Object Name -CEQ $spec.Agent | Select-Object -First 1
                $slot = @($agent.Roles.($spec.Role).Adapters)[$spec.Index]
                Assert ($slot.Name -ceq $spec.Name -and $slot.SchemaVersion -eq 2 -and
                    @($slot.Routes).Count -eq 2 -and $slot.Routes[0].Key -ceq 'primary' -and
                    $slot.Routes[1].Key -ceq 'fallback' -and
                    $slot.Routes[0].Address -ceq $spec.Addresses[0] -and
                    $slot.Routes[1].Address -ceq $spec.Addresses[1]) "SDAFusion two-root route invalid: $($spec.Agent)/$($spec.Role)"
                $resolved = Resolve-StorageResourceRoutesJacket -Jacket $slot -Family EmbeddedFileSystem -AllowUnresolved
                Assert ($resolved.Success() -and @($resolved.GetResult().Addresses).Count -eq 2 -and
                    @($resolved.GetResult().Addresses)[0] -ceq $spec.Addresses[0] -and
                    @($resolved.GetResult().Addresses)[1] -ceq $spec.Addresses[1]) "SDAFusion two-root normalization invalid: $($spec.Agent)/$($spec.Role)"
                $passes += 2
            }
            $secret = @($config.Agents[0].Roles.SDAWorkItems.Adapters)[1]
            Assert ($secret.Name -ceq 'Secrets' -and $secret.SchemaVersion -eq 2 -and
                @($secret.Resource).Count -eq 1 -and $secret.Resource[0].Key -ceq 'vault' -and
                $secret.Resource[0].Vault -ceq 'sda-dev' -and @($secret.Routes).Count -eq 1 -and
                $secret.Routes[0].Key -ceq 'primary' -and $secret.Routes[0].ResourceKey -ceq 'vault' -and
                $secret.Routes[0].Address -ceq 'https://sda-dev.vault.azure.net/') 'SDAFusion Secrets route invalid.'
            $secretResolved = Resolve-StorageResourceRoutesJacket -Jacket $secret -Family AzureKeyVault -AllowUnresolved
            Assert ($secretResolved.Success() -and $secretResolved.GetResult().Resource -ceq 'sda-dev' -and
                @($secretResolved.GetResult().Addresses)[0] -ceq 'https://sda-dev.vault.azure.net/' -and
                (Resolve-StorageResourceRoutesJacket -Jacket $secretResolved.GetResult() -Family AzureKeyVault -ValidateNormalizedV2).Success()) 'SDAFusion Secrets resolver rejected route.'
            $passes += 2
        }
        else { throw 'Unknown ResourceRoutes config fixture shape.' }
    }
}
finally { Remove-Item -LiteralPath $root -Recurse -Force }
"PASS $passes/$passes Foundation storage Resource/Routes assertions"
