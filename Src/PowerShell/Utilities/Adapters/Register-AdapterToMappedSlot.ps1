function Register-AdapterToMappedSlot {
    param (
        [Signal]$ConductorJacketSignal,
        [Signal]$Signal,

        [object]$ConductionContext,

        [Parameter(Mandatory)]
        [object]$Adapter,

        [switch]$Lazy,

        [bool]$RetryFailedResolution = $false
    )

    #Currently treating these as interchangeable, but will want to limit down to one or the other eventually.
    if ($null -eq $ConductorJacketSignal) {
        $ConductorJacketSignal = $Signal
    }
    
    $opSignal = [Signal]::Start("Register-AdapterToMappedSlot") | Select-Object -Last 1

    try {
        function Resolve-AdapterMetadataValue {
            param(
                [object[]]$Candidates,
                [string[]]$Paths
            )

            foreach ($candidate in @($Candidates)) {
                if ($null -eq $candidate) { continue }
                foreach ($path in $Paths) {
                    $valueSignal = Resolve-PathFromDictionary `
                        -Dictionary $candidate `
                        -Path $path `
                        -SignalLevel 'Information' `
                    | Select-Object -Last 1
                    if ($valueSignal.Success() -and $valueSignal.HasResult()) {
                        $value = [string]$valueSignal.GetResult()
                        if (-not [string]::IsNullOrWhiteSpace($value)) {
                            return $value
                        }
                    }
                }
            }
            return $null
        }

        # ░▒▓█ UNWRAP SIGNAL IF NECESSARY █▓▒░
        $resolvedAdapter = if ($Adapter -is [Signal]) {
            $Adapter.GetResult()
        } else {
            $Adapter
        }

        $kind = Resolve-AdapterMetadataValue `
            -Candidates @($Adapter, $resolvedAdapter) `
            -Paths @('$.%.@.Kind', '@.Kind', 'Kind')
        $slot = Resolve-AdapterMetadataValue `
            -Candidates @($Adapter, $resolvedAdapter) `
            -Paths @('$.%.@.Slot', '@.Slot', 'Slot')

        if ([string]::IsNullOrWhiteSpace($kind) -or [string]::IsNullOrWhiteSpace($slot)) {
            $virtualPath = Resolve-AdapterMetadataValue `
                -Candidates @($Adapter, $resolvedAdapter) `
                -Paths @('$.%.@.VirtualPath', '@.VirtualPath', 'VirtualPath')
            if (-not [string]::IsNullOrWhiteSpace($virtualPath)) {
                $virtualPathParts = @($virtualPath -split '\.')
                if ([string]::IsNullOrWhiteSpace($kind) -and $virtualPathParts.Count -ge 3) {
                    $kind = $virtualPathParts[2]
                }
                if ([string]::IsNullOrWhiteSpace($slot)) {
                    if ($virtualPathParts.Count -ge 5) {
                        $slot = $virtualPathParts[4]
                    }
                    elseif ($virtualPathParts.Count -ge 4) {
                        $slot = $virtualPathParts[3]
                    }
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($kind)) {
            $null = $opSignal.LogCritical('Adapter does not contain a resolvable Kind or a valid VirtualPath.')
            return $opSignal
        }

        if ([string]::IsNullOrWhiteSpace($slot)) {
            $null = $opSignal.LogCritical('Adapter does not contain a resolvable Slot or a valid VirtualPath.')
            return $opSignal
        }

        $registrationValue = $resolvedAdapter
        if ($Lazy) {
            $registrationValue = New-AdapterRegistration `
                -Jacket $Adapter `
                -Kind $kind `
                -Slot $slot `
                -ConductionContext $ConductionContext `
                -RetryFailedResolution $RetryFailedResolution
        }

        # ░▒▓█ RESOLVE MAPPED ATTACHMENT CONTAINER █▓▒░
        $mappedPath = "*.#.Adapters.*.#.Mapped$kind"
        $mappedSignal = Resolve-PathFromDictionary -Dictionary $ConductorJacketSignal -Path $mappedPath | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($mappedSignal)) {
            return $opSignal.LogCritical("MappedAdapter path '$mappedPath' not found in Conductor.")
        }

        $mappedAdapterContainer = $mappedSignal.GetResult($true)

        if ($null -eq $mappedAdapterContainer) {
            return $opSignal.LogCritical("MappedAdapter container at '$mappedPath' is null.")
        }

        # ░▒▓█ REGISTER ATTACHMENT █▓▒░
        $registerSignal = $mappedAdapterContainer.RegisterAdapter($registrationValue, $slot) | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifySuccess($registerSignal)) {
            $opSignal.LogInformation("✅ Adapter registered to MappedAdapter slot '$kind'.")
        } else {
            $opSignal.LogWarning("Adapter registration returned warning or soft failure.")
        }

        # Return the value stored in the mapped slot: either an eager adapter
        # instance or a lazy registration handle.
        $opSignal.SetResult($registrationValue)
    }
    catch {
        $opSignal.LogCritical("🔥 Exception during MappedAdapter registration: $($_.Exception.Message)", $null, $_)
    }

    # ░▒▓█ OPTIONAL: MERGE INTO CONDUCTOR CONTROL SIGNAL █▓▒░
    if ($Conductor -and $Conductor.ControlSignal) {
        $Conductor.ControlSignal.MergeSignal($opSignal)
    }

    return $opSignal
}

function Register-AdapterToMappedSlot-NonGrid {
    param (
        [Parameter(Mandatory)]
        [Conductor]$Conductor,

        [Parameter(Mandatory)]
        [object]$Adapter
    )

    $opSignal = [Signal]::Start("Register-AdapterToMappedSlot") | Select-Object -Last 1

    try {
        # ░▒▓█ UNWRAP SIGNAL IF NECESSARY █▓▒░
        $resolvedAdapter = if ($Adapter -is [Signal]) {
            $Adapter.GetResult()
        } else {
            $Adapter
        }

        # ░▒▓█ RESOLVE KIND FROM JACKET █▓▒░
        $kindSignal = Resolve-PathFromDictionary -Dictionary $resolvedAdapter -Path "$.%.@.Kind" | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($kindSignal)) {
            return $opSignal.LogCritical("Adapter does not contain a resolvable 'Jacket.Kind' path.")
        }

        $kind = $kindSignal.GetResult()
        if ([string]::IsNullOrWhiteSpace($kind)) {
            return $opSignal.LogCritical("Adapter Jacket.Kind is empty or null.")
        }

        # ░▒▓█ RESOLVE MAPPED ATTACHMENT CONTAINER █▓▒░
        $mappedPath = "$.*.#.Adapters.*.#.Mapped$($kind)"
        $mappedSignal = Resolve-PathFromDictionary -Dictionary $Conductor -Path $mappedPath | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($mappedSignal)) {
            return $opSignal.LogCritical("MappedAdapter path '$mappedPath' not found in Conductor.")
        }

        $mappedAdapterContainer = $mappedSignal.GetResult()
        if ($null -eq $mappedAdapterContainer) {
            return $opSignal.LogCritical("MappedAdapter container at '$mappedPath' is null.")
        }

        # ░▒▓█ REGISTER ATTACHMENT █▓▒░
        $registerSignal = $mappedAdapterContainer.RegisterAdapter($resolvedAdapter) | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifySuccess($registerSignal)) {
            $opSignal.LogInformation("✅ Adapter registered to MappedAdapter slot '$kind'.")
        } else {
            $opSignal.LogWarning("Adapter registration returned warning or soft failure.")
        }

        # ░▒▓█ RESULT █▓▒░
        $opSignal.SetResult($mappedAdapterContainer)
    }
    catch {
        $opSignal.LogCritical("🔥 Exception during MappedAdapter registration: $($_.Exception.Message)", $null, $_)
    }

    # ░▒▓█ OPTIONAL: MERGE INTO CONDUCTOR CONTROL SIGNAL █▓▒░
    if ($Conductor -and $Conductor.ControlSignal) {
        $Conductor.ControlSignal.MergeSignal($opSignal)
    }

    return $opSignal
}
