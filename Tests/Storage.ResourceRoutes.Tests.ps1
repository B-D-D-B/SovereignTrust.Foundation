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
    [object] Invoke([object]$slot,[object]$activity,[object]$signal,[object]$plan,[object]$itemSignal) {
        $this.Count++
        $merged = $this.Overlay | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        if ($null -eq $merged.PSObject.Properties['Addresses']) { $merged | Add-Member NoteProperty Addresses @('manifest-default') }
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

    # Isolate the real Resolve-AdapterFromJacket seam with provider-free merge/hydration stubs.
    & $module {
        $script:probeType = $args[0]
        $script:hydrationMode = 'resolved'
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
            $jacket = $ItemSignal.GetJacket().GetResult()
            $vaultCase = [string]$jacket.VirtualPath -match '\.AzureKeyVault\.'
            $goodAddress = if ($vaultCase) { 'https://vault.vault.azure.net/' } else { 'C:/hydrated-root' }
            $goodResource = if ($vaultCase) { 'vault' } else { 'hydrated-box' }
            if ($script:hydrationMode -eq 'resolved') {
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
                [pscustomobject]@{ VirtualPath = "SovereignTrust.Adapters.Storage.$family.Probe.Persistent.Read"; SchemaVersion = 2; Routes = @([pscustomobject]@{ Key = 'primary'; Address = $address }) }
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
    } ([StorageRRProbe])
    $passes += 17

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

    if ($ConfigPath) {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -Depth 100
        $slots = @($config.Agents[0].Roles[0].Adapters)
        Assert ($slots.Count -eq 21) 'Config adapter inventory changed.'
        foreach ($name in @('Modules','RemoteMedia','RemoteContent','LocalContent','LocalMedia','LocalMeta','Meta','LocalResources')) {
            $slot = $slots | Where-Object Name -CEQ $name | Select-Object -First 1
            Assert ($slot.SchemaVersion -eq 2 -and @($slot.Routes).Count -eq 1 -and $slot.Routes[0].Key -ceq 'primary') "Config Storage route invalid: $name"
            $passes++
        }
        $passes++
    }
}
finally { Remove-Item -LiteralPath $root -Recurse -Force }
"PASS $passes/$passes Foundation storage Resource/Routes assertions"
