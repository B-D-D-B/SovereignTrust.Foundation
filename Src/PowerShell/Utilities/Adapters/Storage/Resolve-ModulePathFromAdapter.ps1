function Resolve-ModulePathFromAdapter {
    [CmdletBinding()]
    param (
        [Signal]$Signal,
        [MappedStorageAdapter]$Adapter,
        [string]$Slot,
        [string]$RelativePath
    )

    $opSignal = [Signal]::Start("Get-ModulePathFromAdapter") | Select-Object -Last 1

    try {
        $root = Resolve-PathFromDictionary -Dictionary $Adapter -Path "$.*.#.$Slot" | Select-Object -Last 1
        if (-not $root.Success()) {
            return $opSignal.MergeSignal($root).LogCritical("Could not resolve root address from adapter.")
        }

        $rootAdapterSignal = $root.GetResult()
        if ($rootAdapterSignal -isnot [Signal]) {
            $rootAdapterSignal = $root.GetResultSignal()
        }

        $resolvedRootSignal = Resolve-MappedAdapter `
            -AdapterSignal $rootAdapterSignal `
            -Signal $Signal `
            -ConductionContext $Signal `
        | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($resolvedRootSignal) -or -not $resolvedRootSignal.HasResult()) {
            $opSignal.LogCritical("Could not resolve storage adapter in slot '$Slot'.")
            return $opSignal
        }

        $rootAdapter = $resolvedRootSignal.GetResult()

        $addressesSignal = Resolve-PathFromDictionary -Dictionary $rootAdapter -Path "$.%.@.Addresses" | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($addressesSignal) -or -not $addressesSignal.HasResult()) {
            $opSignal.LogCritical("Storage adapter in slot '$Slot' does not contain root addresses.")
            return $opSignal
        }

        $addresses = $addressesSignal.GetResult()

        foreach ($address in $addresses) {
            $fullPath = Join-Path -Path $address -ChildPath $RelativePath
            if ((Test-Path $fullPath)) {
                $opSignal.SetResult($fullPath)
                $opSignal.LogInformation("📦 Resolved module path: $fullPath")
                break;
            }
        }

        if (-not $opSignal.HasResult()) {
            $opSignal.LogCritical("Could not resolve module path for '$RelativePath' in slot '$Slot'.")
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception while resolving module path: $_", $null, $_)
    }

    return $opSignal
}
