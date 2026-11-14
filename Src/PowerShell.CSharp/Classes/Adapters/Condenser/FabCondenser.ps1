# =============================================================================
# 🧩 FabCondenser (Symbolic Mapping + Contextual Replacement)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☠️🧁👾️/🤖 • Neural Alchemist ⚗️☣️🐲 • Last Updated: 07/12/2025
# =============================================================================
# Performs template condensation using dynamic mappings and embedded context.
# Resolves tags such as `@@TAG`, `##TAG`, `<TAG />` using sovereign source maps.
# Often used in Condenser chains during token hydration, agent bootstrap, or
# reactive publishing from flattened proposal schemas.
# =============================================================================

<#
Class: FabCondenser
Purpose: Perform fab condenser operations.
ContractStatus: Enforced
ActivityScope: AdapterAgnostic
Activities:
- Invoke: Fabricate or resolve an adapter from a plan.
- ObserveMappedAdapter: Resolve a selected mapped adapter and report its observed identity. First use can import and construct it; no provider activity is invoked. Invalid provenance fails without a result.
ActivityValidation: OnInvoke, BeforeDispatch
UnsupportedActivity: FailedSignal
ActivityComparison: CaseInsensitive
#>
class FabCondenser {
    [Conductor]$Conductor
    [MappedCondenserAdapter]$MappedCondenserAdapter
    [Signal]$Signal  # Previously ControlSignal

    FabCondenser() {
        # Empty constructor — use .Start()
    }
       
    static [FabCondenser] Start([MappedCondenserAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [FabCondenser]::new()
        $instance.MappedCondenserAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("FabCondenser.Control") | Select-Object -Last 1
        return $instance
    }

    [Signal]Invoke($Slot, $Activity, $Signal, $Plan, $ItemSignal) {
        $opSignal = [Signal]::Start("FabCondenser.Invoke", $ItemSignal) | Select-Object -Last 1

        if ($Activity -notin @('Invoke', 'ObserveMappedAdapter')) {
            $opSignal.LogCritical("Unsupported FabCondenser activity: '$Activity'.")
            return $opSignal
        }

        if ($Activity -eq 'ObserveMappedAdapter') {
            return $this.ObserveMappedAdapter($Signal, $Plan, $ItemSignal)
        }

        $JacketSignalWrapper = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path "%" | Select-Object -Last 1
        $JacketSignal = $JacketSignalWrapper.GetResult()
        try {
            $source = $JacketSignal
            while ($source -is [Signal]) { $source = $source.GetResult($true) }
            $sourcePath = [string]$source.VirtualPath
            $parts = @($sourcePath -split '\.')
            if ($parts.Count -lt 5 -or [string]::IsNullOrWhiteSpace($parts[2]) -or
                [string]::IsNullOrWhiteSpace($parts[4]) -or
                (-not [string]::IsNullOrWhiteSpace([string]$source.Kind) -and [string]$source.Kind -cne $parts[2]) -or
                (-not [string]::IsNullOrWhiteSpace([string]$source.Slot) -and [string]$source.Slot -cne $parts[4])) {
                $opSignal.LogCritical('Selected source jacket has no consistent Kind, Slot and VirtualPath.')
                return $opSignal
            }
            $sourceIdentity = [pscustomobject]@{
                Kind = [string]$parts[2]
                Slot = [string]$parts[4]
                VirtualPath = [string]$sourcePath
            }
        }
        catch {
            $opSignal.LogCritical("Selected source jacket cannot be inspected: $($_.Exception.Message)", $null, $_)
            return $opSignal
        }
        $loadingMode = 'Lazy'
        $retryFailedResolution = $false
        if ($null -ne $Plan) {
            $loadingModeSignal = Resolve-PathFromDictionary `
                -Dictionary $Plan `
                -Path 'Config.AdapterLoading.Mode' `
                -Default $loadingMode `
                -SignalLevel 'Information' `
            | Select-Object -Last 1
            $retrySignal = Resolve-PathFromDictionary `
                -Dictionary $Plan `
                -Path 'Config.AdapterLoading.RetryFailedResolution' `
                -Default $retryFailedResolution `
                -SignalLevel 'Information' `
            | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure(@($loadingModeSignal, $retrySignal))) {
                return $opSignal
            }

            $loadingMode = [string]$loadingModeSignal.GetResult()
            $retryFailedResolution = [bool]$retrySignal.GetResult()
        }

        $useLazyLoading = $loadingMode -ne 'Eager'
        if ($useLazyLoading) {
            $addSignal = Register-AdapterToMappedSlot `
                -ConductorJacketSignal $Signal.GetJacket() `
                -Signal $Signal `
                -ConductionContext $Signal `
                -Adapter $JacketSignal `
                -Lazy `
                -RetryFailedResolution $retryFailedResolution `
            | Select-Object -Last 1
        }
        else {
            $resolveAdapterSignal = Resolve-AdapterFromJacket `
                -Signal $Signal `
                -ConductionContext $Signal `
                -Jacket $JacketSignal `
            | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure($resolveAdapterSignal) -or -not $resolveAdapterSignal.HasResult()) {
                return $opSignal
            }

            $addSignal = Register-AdapterToMappedSlot `
                -ConductorJacketSignal $Signal.GetJacket() `
                -Signal $Signal `
                -ConductionContext $Signal `
                -Adapter $resolveAdapterSignal `
            | Select-Object -Last 1
        }

        if ($opSignal.MergeSignalAndVerifyFailure($addSignal)) {
            $opSignal.LogCritical("Failed to add adapter to appropriate Mapped Adapter.")
            return $opSignal
        }

        try {
            if (-not $addSignal.HasResult()) { throw 'Mapped registration returned no handle.' }
            $mappedResult = Resolve-PathFromDictionary -Dictionary $this.Conductor.Signal -Path "*.#.Adapters.*.#.Mapped$($sourceIdentity.Kind)" | Select-Object -Last 1
            if (-not $mappedResult.Success() -or -not $mappedResult.HasResult()) { throw 'Mapped container is unavailable after registration.' }
            $mapped = $mappedResult.GetResult($true)
            $graph = $mapped.Signal.GetPointer()
            if ($graph -isnot [Graph] -or $null -eq $graph.Grid -or -not $graph.Grid.Contains($sourceIdentity.Slot)) {
                throw 'Selected slot was not stored in the mapped graph.'
            }
            $slotSignal = $graph.Grid[$sourceIdentity.Slot]
            if ($slotSignal -isnot [Signal] -or -not [object]::ReferenceEquals($slotSignal.GetResult($true), $addSignal.GetResult())) {
                throw 'Stored slot differs from the registration result.'
            }
            $null = $slotSignal.AddProperty('FabSourceIdentity', $sourceIdentity)
            if (-not [object]::ReferenceEquals($slotSignal.GetProperty('FabSourceIdentity'), $sourceIdentity)) {
                throw 'Selected source identity was not retained on the mapped slot.'
            }
        }
        catch {
            $opSignal.LogCritical("Mapped registration has partial state; source identity attachment failed: $($_.Exception.Message)", $null, $_)
            return $opSignal
        }

        $opSignal.SetResult($addSignal.GetResult())

        return $opSignal
    }

    [Signal] ObserveMappedAdapter([Signal]$Signal, [object]$Plan, [Signal]$ItemSignal) {
        $opSignal = [Signal]::Start('FabCondenser.ObserveMappedAdapter', $ItemSignal) | Select-Object -Last 1
        try {
            $kind = [string]$Plan.Config.Kind
            $slot = [string]$Plan.Config.Slot
            $absentSlot = [string]$Plan.Config.AbsentSlot
            if ([string]::IsNullOrWhiteSpace($kind) -or [string]::IsNullOrWhiteSpace($slot) -or
                [string]::IsNullOrWhiteSpace($absentSlot) -or $slot -eq $absentSlot -or
                $kind -notmatch '^[A-Za-z]+$' -or $slot -notmatch '^[A-Za-z0-9_-]+$' -or
                $absentSlot -notmatch '^[A-Za-z0-9_-]+$') {
                $opSignal.LogCritical('ObserveMappedAdapter requires distinct, nonempty Kind, Slot and AbsentSlot.')
                return $opSignal
            }

            $mappedResult = Resolve-PathFromDictionary -Dictionary $this.Conductor.Signal -Path "* .#.Adapters.*.#.Mapped$kind".Replace(' ', '') -SignalLevel 'Information' | Select-Object -Last 1
            if (-not $mappedResult.Success() -or -not $mappedResult.HasResult()) {
                $opSignal.LogCritical("Mapped$kind is missing.")
                return $opSignal
            }
            $mapped = $mappedResult.GetResult($true)
            $graph = $mapped.Signal.GetPointer()
            if ($graph -isnot [Graph] -or $null -eq $graph.Grid) {
                $opSignal.LogCritical("Mapped$kind graph is unavailable.")
                return $opSignal
            }
            if (-not $graph.Grid.Contains($slot)) {
                $opSignal.LogCritical("Mapped$kind slot '$slot' is missing.")
                return $opSignal
            }
            $slotSignal = $graph.Grid[$slot]
            if ($slotSignal -isnot [Signal] -or -not $slotSignal.HasResult()) {
                $opSignal.LogCritical("Mapped$kind slot '$slot' has no registration or instance.")
                return $opSignal
            }
            $source = $slotSignal.GetProperty('FabSourceIdentity')
            $sourcePath = [string]$source.VirtualPath
            $parts = @($sourcePath -split '\.')
            if ($null -eq $source -or $parts.Count -lt 5 -or $parts[2] -cne $kind -or $parts[4] -cne $slot -or
                [string]$source.Kind -cne $kind -or [string]$source.Slot -cne $slot) {
                $opSignal.LogCritical('Mapped slot has no matching Fab source identity.')
                return $opSignal
            }
            $before = $slotSignal.GetResult($true)
            $wasRegistration = $null -ne $before -and [bool]$before.IsAdapterRegistration
            $missingSlotAbsent = -not $graph.Grid.Contains($absentSlot)

            $resolved = Resolve-MappedAdapter -AdapterSignal $slotSignal -Signal $Signal -ConductionContext $mapped.Signal.GetJacket() | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure($resolved) -or -not $resolved.HasResult()) {
                if (-not $opSignal.Failure()) { $opSignal.LogCritical('Mapped adapter resolution returned no instance.') }
                return $opSignal
            }
            $instance = $resolved.GetResult()
            if ($null -eq $instance -or $null -eq $instance.Signal -or $null -eq $instance.Signal.GetJacket()) {
                $opSignal.LogCritical('Resolved instance has no constructed jacket.')
                return $opSignal
            }
            if ($wasRegistration -and ($before.State -cne 'Resolved' -or -not [object]::ReferenceEquals($before.Instance, $instance) -or
                -not [object]::ReferenceEquals($slotSignal.GetResult($true), $instance))) {
                $opSignal.LogCritical('Lazy registration did not transition to the cached instance.')
                return $opSignal
            }
            $jacket = $instance.Signal.GetJacket().GetResult()
            if ($jacket -is [Signal]) { $jacket = $jacket.GetResult() }
            $instancePath = [string]$jacket.VirtualPath
            if ([string]$jacket.Kind -cne $kind -or [string]$jacket.Slot -cne $slot -or
                [string]::IsNullOrWhiteSpace($instancePath)) {
                $opSignal.LogCritical('Constructed jacket identity is missing or mismatched.')
                return $opSignal
            }

            $formula = Resolve-ModulePathSignal -WirePath $sourcePath | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure($formula) -or -not $formula.HasResult()) { return $opSignal }
            $derived = $formula.GetResult().GetJacket().GetResult()
            if ($instance.GetType().Name -cne [string]$derived.FullType) {
                $opSignal.LogCritical('Resolved instance type does not match the source-selected type.')
                return $opSignal
            }
            $storageResult = Resolve-PathFromDictionary -Dictionary $this.Conductor.Signal -Path '* .#.Adapters.*.#.MappedStorage'.Replace(' ', '') | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure($storageResult) -or -not $storageResult.HasResult()) { return $opSignal }
            $manifestResult = Resolve-ModulePathFromAdapter -Signal $Signal -Adapter $storageResult.GetResult($true) -Slot 'ModuleRoots' -RelativePath ([string]$derived.RelativeFilePath) | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure($manifestResult) -or -not $manifestResult.HasResult()) { return $opSignal }
            $manifestPath = [System.IO.Path]::GetFullPath([string]$manifestResult.GetResult())
            $manifest = Import-PowerShellDataFile -Path $manifestPath
            $rootModule = [string]$manifest.RootModule
            if ([string]::IsNullOrWhiteSpace($rootModule)) {
                $opSignal.LogCritical('Selected module manifest has no RootModule.')
                return $opSignal
            }
            $rootPath = [System.IO.Path]::GetFullPath((Join-Path (Split-Path $manifestPath -Parent) $rootModule))
            $modules = @(Get-Module -Name ([System.IO.Path]::GetFileNameWithoutExtension($rootModule)) | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.Path) -and
                [System.IO.Path]::GetFullPath($_.Path) -ieq $rootPath
            })
            if ($modules.Count -ne 1 -or $modules[0].Name -cne [System.IO.Path]::GetFileNameWithoutExtension($rootModule)) {
                $opSignal.LogCritical('Loaded module identity is missing or ambiguous.')
                return $opSignal
            }
            $opSignal.SetResult([pscustomobject]@{
                SourceMapping = [bool]($sourcePath -ceq $instancePath -and [string]$source.Kind -ceq $kind -and [string]$source.Slot -ceq $slot)
                ModuleName = [string]$modules[0].Name
                ClassName = [string]$instance.GetType().Name
                MappedSlot = [string]$slot
                JacketVirtualPath = [string]$instancePath
                MissingSlotAbsent = [bool]$missingSlotAbsent
            })
        }
        catch {
            $opSignal.LogCritical("Mapped adapter observation failed: $($_.Exception.Message)", $null, $_)
        }
        return $opSignal
    }
}
