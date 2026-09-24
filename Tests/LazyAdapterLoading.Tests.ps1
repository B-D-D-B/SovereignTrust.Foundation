using module ../../SignalGraph/Src/PowerShell/SignalGraph.psd1

$ErrorActionPreference = 'Stop'
$foundationRoot = Join-Path $PSScriptRoot '../Src/PowerShell'

class Conductor {}
class MappedCondenserAdapter {}

. "$foundationRoot/Utilities/Adapters/New-AdapterRegistration.ps1"
. "$foundationRoot/Utilities/Adapters/Resolve-RegisteredAdapter.ps1"
. "$foundationRoot/Utilities/Adapters/Resolve-MappedAdapter.ps1"
. "$foundationRoot/Utilities/Adapters/Register-AdapterToMappedSlot.ps1"
. "$foundationRoot/Utilities/Adapters/Storage/Resolve-ModulePathFromAdapter.ps1"
. "$foundationRoot/Classes/Adapters/Condenser/FabCondenser.ps1"
. "$foundationRoot/Classes/Adapters/MappedStorageAdapter.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$script:resolutionCount = 0
$script:failNextResolution = $false

function Resolve-AdapterFromJacket {
    param(
        [Signal]$Signal,
        [object]$ConductionContext,
        [object]$Jacket
    )

    $script:resolutionCount++
    $resultSignal = [Signal]::Start('TestAdapterResolution', $Signal) | Select-Object -Last 1
    if ($script:failNextResolution) {
        $script:failNextResolution = $false
        $null = $resultSignal.LogCritical('Expected test resolution failure.')
        return $resultSignal
    }

    $resultSignal.SetResult([PSCustomObject]@{
        Id      = [guid]::NewGuid().ToString()
        Context = $ConductionContext
        Jacket  = $Jacket
    })
    return $resultSignal
}

$signal = [Signal]::Start('LazyAdapterTest') | Select-Object -Last 1
$context = [PSCustomObject]@{ Name = 'TestContext' }
$jacket = [PSCustomObject]@{ Name = 'TestJacket' }
$registration = New-AdapterRegistration -Jacket $jacket -Kind 'Storage' -Slot 'TestStorage'
$adapterSignal = [Signal]::Start('Adapter:TestStorage') | Select-Object -Last 1
$adapterSignal.SetResult($registration)

$firstSignal = Resolve-MappedAdapter -AdapterSignal $adapterSignal -Signal $signal -ConductionContext $context | Select-Object -Last 1
Assert-True (-not $firstSignal.Failure() -and $firstSignal.HasResult()) 'First lazy resolution failed.'
$firstInstance = $firstSignal.GetResult()
Assert-True ($script:resolutionCount -eq 1) 'First use did not construct exactly one adapter.'
Assert-True ($registration.State -eq 'Resolved') 'Registration was not marked Resolved.'

$secondSignal = Resolve-RegisteredAdapter -Registration $registration -Signal $signal -ConductionContext $context | Select-Object -Last 1
Assert-True (-not $secondSignal.Failure() -and $secondSignal.HasResult()) 'Cached lazy resolution failed.'
Assert-True ([object]::ReferenceEquals($firstInstance, $secondSignal.GetResult())) 'Second use did not reuse the cached adapter.'
Assert-True ($script:resolutionCount -eq 1) 'Cached use constructed another adapter.'

$eagerInstance = [PSCustomObject]@{ Name = 'EagerAdapter' }
$eagerSignal = Resolve-RegisteredAdapter -Registration $eagerInstance -Signal $signal -ConductionContext $context | Select-Object -Last 1
Assert-True ([object]::ReferenceEquals($eagerInstance, $eagerSignal.GetResult())) 'Eager adapter passthrough changed the instance.'

$storedContext = [PSCustomObject]@{ Name = 'StoredFabContext' }
$fallbackContext = [PSCustomObject]@{ Name = 'FirstUseContext' }
$storedContextRegistration = New-AdapterRegistration `
    -Jacket $jacket `
    -Kind 'Storage' `
    -Slot 'StoredContext' `
    -ConductionContext $storedContext
$storedContextSignal = Resolve-RegisteredAdapter `
    -Registration $storedContextRegistration `
    -Signal $signal `
    -ConductionContext $fallbackContext `
| Select-Object -Last 1
Assert-True (-not $storedContextSignal.Failure() -and $storedContextSignal.HasResult()) 'Stored-context lazy resolution failed.'
Assert-True ([object]::ReferenceEquals($storedContext, $storedContextSignal.GetResult().Context)) 'Lazy resolution did not prefer its stored Fab-time context.'

$script:failNextResolution = $true
$failedRegistration = New-AdapterRegistration -Jacket $jacket -Kind 'Storage' -Slot 'FailedStorage'
$failedSignal = Resolve-RegisteredAdapter -Registration $failedRegistration -Signal $signal -ConductionContext $context | Select-Object -Last 1
Assert-True ($failedSignal.Failure()) 'Failed lazy resolution did not return a critical signal.'
Assert-True ($failedRegistration.State -eq 'Failed') 'Failed registration did not retain Failed state.'
$countAfterFailure = $script:resolutionCount
$failedAgainSignal = Resolve-RegisteredAdapter -Registration $failedRegistration -Signal $signal -ConductionContext $context | Select-Object -Last 1
Assert-True ($failedAgainSignal.Failure()) 'Non-retryable failed registration unexpectedly succeeded.'
Assert-True ($script:resolutionCount -eq $countAfterFailure) 'Non-retryable failure invoked the resolver again.'

$script:failNextResolution = $true
$retryRegistration = New-AdapterRegistration `
    -Jacket $jacket `
    -Kind 'Storage' `
    -Slot 'RetryStorage' `
    -RetryFailedResolution $true
$retryFailureSignal = Resolve-RegisteredAdapter -Registration $retryRegistration -Signal $signal -ConductionContext $context | Select-Object -Last 1
Assert-True ($retryFailureSignal.Failure()) 'Retry test did not fail on its first resolution.'
$retrySuccessSignal = Resolve-RegisteredAdapter -Registration $retryRegistration -Signal $signal -ConductionContext $context | Select-Object -Last 1
Assert-True (-not $retrySuccessSignal.Failure() -and $retrySuccessSignal.HasResult()) 'Retryable registration did not recover.'
Assert-True ($retryRegistration.State -eq 'Resolved') 'Recovered registration was not marked Resolved.'

$mappedStorage = [PSCustomObject]@{
    RegisteredAdapter = $null
    RegisteredSlot    = $null
}
$mappedStorage | Add-Member -MemberType ScriptMethod -Name RegisterAdapter -Value {
    param($Adapter, $Slot)
    $this.RegisteredAdapter = $Adapter
    $this.RegisteredSlot = $Slot
    $registerSignal = [Signal]::Start("Register:$Slot") | Select-Object -Last 1
    $registerSignal.SetResult($Adapter)
    return $registerSignal
}

$conductorSignal = [Signal]::Start('ConductorJacket') | Select-Object -Last 1
$conductorGraph = ([Graph]::Start('ConductorGraph', $conductorSignal, $false) | Select-Object -Last 1).GetResult()
$null = $conductorSignal.SetPointer($conductorGraph)
$adaptersSignal = [Signal]::Start('Adapters') | Select-Object -Last 1
$adaptersGraph = ([Graph]::Start('AdaptersGraph', $adaptersSignal, $false) | Select-Object -Last 1).GetResult()
$null = $adaptersSignal.SetPointer($adaptersGraph)
$null = $conductorGraph.RegisterSignal('Adapters', $adaptersSignal)
$mappedStorageSignal = [Signal]::Start('MappedStorage') | Select-Object -Last 1
$mappedStorageSignal.SetResult($mappedStorage)
$null = $adaptersGraph.RegisterSignal('MappedStorage', $mappedStorageSignal)

$adapterJacket = [Signal]::Start('LazyStorageJacket') | Select-Object -Last 1
$adapterJacket.SetResult([PSCustomObject]@{
    Name        = 'LazyStorage'
    Kind        = 'Storage'
    Slot        = 'LazyStorage'
    VirtualPath = 'SovereignTrust.Adapters.Storage.LazyStorage'
})
$registrationSignal = Register-AdapterToMappedSlot `
    -ConductorJacketSignal $conductorSignal `
    -Signal $signal `
    -ConductionContext $context `
    -Adapter $adapterJacket `
    -Lazy `
| Select-Object -Last 1

Assert-True (-not $registrationSignal.Failure() -and $registrationSignal.HasResult()) 'Lazy mapped-slot registration failed.'
Assert-True ([bool]$mappedStorage.RegisteredAdapter.IsAdapterRegistration) 'Fab-style registration constructed an adapter instead of storing a definition.'
Assert-True ($mappedStorage.RegisteredSlot -eq 'LazyStorage') 'Lazy registration used the wrong mapped slot.'
Assert-True ([object]::ReferenceEquals($adapterJacket, $mappedStorage.RegisteredAdapter.Jacket)) 'Lazy registration did not preserve the source jacket.'
Assert-True ([object]::ReferenceEquals($context, $mappedStorage.RegisteredAdapter.ConductionContext)) 'Lazy registration did not preserve its Fab-time conduction context.'

$virtualPathOnlyJacket = [Signal]::Start('VirtualPathOnlyJacket') | Select-Object -Last 1
$null = $virtualPathOnlyJacket.SetResult([PSCustomObject]@{
    VirtualPath = 'SovereignTrust.Adapters.Storage.EmbeddedFileSystem.Content.Persistent.Read'
    Addresses   = @('TestContent')
})
$virtualPathRegistrationSignal = Register-AdapterToMappedSlot `
    -ConductorJacketSignal $conductorSignal `
    -Signal $signal `
    -ConductionContext $context `
    -Adapter $virtualPathOnlyJacket `
    -Lazy `
| Select-Object -Last 1

Assert-True (-not $virtualPathRegistrationSignal.Failure() -and $virtualPathRegistrationSignal.HasResult()) 'VirtualPath-only lazy registration failed.'
$virtualPathRegistration = $virtualPathRegistrationSignal.GetResult()
Assert-True ($virtualPathRegistration.Kind -eq 'Storage') 'VirtualPath did not derive the Storage kind.'
Assert-True ($virtualPathRegistration.Slot -eq 'Content') 'VirtualPath did not derive the Content slot.'
Assert-True ($mappedStorage.RegisteredSlot -eq 'Content') 'VirtualPath-derived registration used the wrong mapped slot.'

$script:nullPlanRegistration = $null
function Register-AdapterToMappedSlot {
    param(
        [Signal]$ConductorJacketSignal,
        [Signal]$Signal,
        [object]$ConductionContext,
        [object]$Adapter,
        [switch]$Lazy,
        [bool]$RetryFailedResolution
    )

    $script:nullPlanRegistration = [PSCustomObject]@{
        Lazy                  = $Lazy.IsPresent
        RetryFailedResolution = $RetryFailedResolution
        Adapter               = $Adapter
    }
    $resultSignal = [Signal]::Start('NullPlanRegistration') | Select-Object -Last 1
    $resultSignal.SetResult($script:nullPlanRegistration)
    return $resultSignal
}

$fabSignal = [Signal]::Start('NullPlanFabSignal') | Select-Object -Last 1
$null = $fabSignal.SetJacket($conductorSignal)
$fabItemSignal = [Signal]::Start('NullPlanFabItem') | Select-Object -Last 1
$null = $fabItemSignal.SetJacket($adapterJacket)
$fabCondenser = New-Object -TypeName FabCondenser
$nullPlanSignal = $fabCondenser.Invoke('Fab', 'Invoke', $fabSignal, $null, $fabItemSignal)

Assert-True (-not $nullPlanSignal.Failure() -and $nullPlanSignal.HasResult()) 'Fab invocation with a null Plan failed.'
Assert-True $script:nullPlanRegistration.Lazy 'Null Plan did not default Fab to lazy adapter loading.'
Assert-True (-not $script:nullPlanRegistration.RetryFailedResolution) 'Null Plan did not default retry to false.'

$script:capturedResolutionContext = $null
$resolvedStorageConfigSignal = [Signal]::Start('ResolvedStorageConfig') | Select-Object -Last 1
$null = $resolvedStorageConfigSignal.SetResult([PSCustomObject]@{ Addresses = @($PSScriptRoot) })
$resolvedStorageInstanceSignal = [Signal]::Start('ResolvedStorageInstance') | Select-Object -Last 1
$null = $resolvedStorageInstanceSignal.SetJacket($resolvedStorageConfigSignal)
$resolvedStorageAdapter = [PSCustomObject]@{ Signal = $resolvedStorageInstanceSignal }
$resolvedStorageAdapter | Add-Member -MemberType ScriptMethod -Name Invoke -Value {
    param($Slot, $Activity, $ConductionSignal, $Plan, $ItemSignal)
    $resultSignal = [Signal]::Start('StorageInvocation') | Select-Object -Last 1
    $resultSignal.SetResult('StorageResult')
    return $resultSignal
}
function Resolve-MappedAdapter {
    param(
        [Signal]$AdapterSignal,
        [Signal]$Signal,
        [object]$ConductionContext
    )

    $script:capturedResolutionContext = $ConductionContext
    $resultSignal = [Signal]::Start('CapturedStorageResolution') | Select-Object -Last 1
    $resultSignal.SetResult($resolvedStorageAdapter)
    return $resultSignal
}

$mappedStorageAdapter = New-Object -TypeName MappedStorageAdapter
$mappedStorageSignal = [Signal]::Start('MappedStorageContextTest') | Select-Object -Last 1
$mappedStorageGraph = ([Graph]::Start('MappedStorageContextGraph', $mappedStorageSignal, $false) | Select-Object -Last 1).GetResult()
$null = $mappedStorageSignal.SetPointer($mappedStorageGraph)
$null = $mappedStorageSignal.SetResult($mappedStorageGraph)
$registeredStorageSignal = [Signal]::Start('Adapter:Content') | Select-Object -Last 1
$registeredStorageSignal.SetResult([PSCustomObject]@{ Name = 'RegistrationPlaceholder' })
$null = $mappedStorageGraph.RegisterSignal('Content', $registeredStorageSignal)
$registeredModuleRootsSignal = [Signal]::Start('Adapter:ModuleRoots') | Select-Object -Last 1
$registeredModuleRootsSignal.SetResult([PSCustomObject]@{ Name = 'LazyModuleRootsRegistration' })
$null = $mappedStorageGraph.RegisterSignal('ModuleRoots', $registeredModuleRootsSignal)
$mappedStorageAdapter.Signal = $mappedStorageSignal

$activeConductionSignal = [Signal]::Start('ActiveStorageConduction') | Select-Object -Last 1
$storagePlan = [PSCustomObject]@{
    Config = [PSCustomObject]@{ VirtualPath = 'Config/SDAFusionApp.Json' }
}
$storageItemSignal = [Signal]::Start('StorageItem') | Select-Object -Last 1
$storageInvocationSignal = $mappedStorageAdapter.Invoke(
    'Content',
    'Read',
    $activeConductionSignal,
    $storagePlan,
    $storageItemSignal
)

Assert-True (-not $storageInvocationSignal.Failure()) 'Mapped storage context regression invocation failed.'
Assert-True ([object]::ReferenceEquals($activeConductionSignal, $script:capturedResolutionContext)) 'Mapped storage did not use the active conduction signal for lazy resolution.'

$modulePathSignal = Resolve-ModulePathFromAdapter `
    -Signal $activeConductionSignal `
    -Adapter $mappedStorageAdapter `
    -Slot 'ModuleRoots' `
    -RelativePath 'Fixtures\TestRunspaceWorker.psm1' `
| Select-Object -Last 1
Assert-True (-not $modulePathSignal.Failure() -and $modulePathSignal.HasResult()) 'Lazy ModuleRoots adapter did not resolve a module path.'
Assert-True ($modulePathSignal.GetResult() -eq (Join-Path $PSScriptRoot 'Fixtures\TestRunspaceWorker.psm1')) 'Lazy ModuleRoots adapter returned the wrong module path.'

Write-Output 'PASS: lazy registration, VirtualPath metadata, construction context, ModuleRoots lookup, cached reuse, eager passthrough, failure retention, retry behavior, and null-Plan defaults.'
