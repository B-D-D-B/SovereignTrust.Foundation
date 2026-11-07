function Resolve-StorageResourceRoutesJacket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Jacket,
        [Parameter(Mandatory)][ValidateSet('AzureStorageAccount','AzureKeyVault','EmbeddedFileSystem','LocalFileSystem')][string]$Family,
        [switch]$AllowUnresolved,
        [switch]$ValidateNormalizedV2
    )

    $result = [Signal]::Start('Resolve-StorageResourceRoutesJacket') | Select-Object -Last 1
    try {
        $value = if ($Jacket -is [Signal]) { $Jacket.GetResult($true) } else { $Jacket }
        if ($null -eq $value) { return $result.LogCritical('Storage jacket is absent.') }
        $get = {
            param($object, [string]$name)
            if ($object -is [System.Collections.IDictionary]) {
                foreach ($key in $object.Keys) { if ([string]$key -ceq $name) { return ,$object[$key] } }
                return $null
            }
            $property = $object.PSObject.Properties | Where-Object Name -CEQ $name | Select-Object -First 1
            if ($null -ne $property) { return ,$property.Value }
            return $null
        }
        $has = {
            param($object, [string]$name)
            if ($object -is [System.Collections.IDictionary]) {
                foreach ($key in $object.Keys) { if ([string]$key -ceq $name) { return $true } }
                return $false
            }
            return $null -ne ($object.PSObject.Properties | Where-Object Name -CEQ $name | Select-Object -First 1)
        }
        $valid = {
            param($field)
            return $field -is [string] -and -not [string]::IsNullOrWhiteSpace($field) -and
                ($AllowUnresolved -or $field -notmatch '\[[A-Za-z][A-Za-z0-9_.]*\.')
        }
        if ($ValidateNormalizedV2) {
            $addresses = & $get $value 'Addresses'
            if ($null -eq $addresses -or @($addresses).Count -ne 1 -or -not (& $valid @($addresses)[0])) {
                return $result.LogCritical('Storage v2 selected Address is invalid after hydration.')
            }
            if ($Family -in @('AzureStorageAccount','AzureKeyVault') -and -not (& $valid (& $get $value 'Resource'))) {
                return $result.LogCritical('Storage v2 selected Resource is invalid after hydration.')
            }
            if ($Family -eq 'AzureKeyVault') {
                $vaultName = & $get $value 'Resource'
                $uri = $null
                if ($vaultName -notmatch '^[A-Za-z0-9-]+$' -or
                    -not [uri]::TryCreate([string]@($addresses)[0], [UriKind]::Absolute, [ref]$uri) -or
                    $uri.Scheme -cne 'https' -or $uri.AbsolutePath.Trim('/') -ne '' -or
                    $uri.Host -ine "$vaultName.vault.azure.net") {
                    return $result.LogCritical('Storage v2 selected Vault route is invalid after hydration.')
                }
            }
            $result.SetResult($value)
            return $result
        }

        $version = & $get $value 'SchemaVersion'
        $hasRoutes = & $has $value 'Routes'
        if ($null -eq $version -and -not $hasRoutes -and ((& $get $value 'Resource') -isnot [array])) {
            $result.SetResult($value)
            return $result
        }
        if (($version -isnot [long] -and $version -isnot [int]) -or $version -ne 2 -or -not $hasRoutes -or
            (& $has $value 'Addresses') -or (& $has $value 'Address')) {
            return $result.LogCritical('Storage v2 jacket has an invalid or mixed envelope.')
        }
        $routes = & $get $value 'Routes'
        if ($routes -isnot [array] -or $routes.Count -ne 1) {
            return $result.LogCritical('Storage v2 requires one primary Route.')
        }
        $route = $routes[0]
        $routeFields = if ($route -is [System.Collections.IDictionary]) { @($route.Keys) } else { @($route.PSObject.Properties.Name) }
        $allowedRouteFields = if ($Family -in @('AzureStorageAccount','AzureKeyVault')) { @('Key','Address','ResourceKey') } else { @('Key','Address') }
        if (@($routeFields | Where-Object { $_ -cnotin $allowedRouteFields }).Count -gt 0 -or
            @($routeFields).Count -ne $allowedRouteFields.Count) {
            return $result.LogCritical('Storage v2 Route fields are invalid.')
        }
        if ((& $get $route 'Key') -cne 'primary' -or -not (& $valid (& $get $route 'Address'))) {
            return $result.LogCritical('Storage v2 primary Route is invalid.')
        }
        if ($Family -in @('AzureStorageAccount','AzureKeyVault')) {
            $resources = & $get $value 'Resource'
            if ($resources -is [array] -and $resources.Count -eq 1) {
                $resourceFields = if ($resources[0] -is [System.Collections.IDictionary]) { @($resources[0].Keys) } else { @($resources[0].PSObject.Properties.Name) }
                $allowedResourceFields = if ($Family -eq 'AzureKeyVault') { @('Key','Vault') } else { @('Key','Container') }
                if (@($resourceFields | Where-Object { $_ -cnotin $allowedResourceFields }).Count -gt 0 -or
                    @($resourceFields).Count -ne 2) {
                    return $result.LogCritical('Storage v2 Resource fields are invalid.')
                }
            }
            $resourceKey = if ($Family -eq 'AzureKeyVault') { 'vault' } else { 'container' }
            $resourceField = if ($Family -eq 'AzureKeyVault') { 'Vault' } else { 'Container' }
            if ($resources -isnot [array] -or $resources.Count -ne 1 -or
                (& $get $resources[0] 'Key') -cne $resourceKey -or
                (& $get $route 'ResourceKey') -cne $resourceKey -or
                -not (& $valid (& $get $resources[0] $resourceField))) {
                return $result.LogCritical('Storage v2 Resource reference is invalid.')
            }
            if ($Family -eq 'AzureKeyVault') {
                $vaultName = & $get $resources[0] 'Vault'
                $address = & $get $route 'Address'
                if ($vaultName -notmatch '^[A-Za-z0-9-]+$' -and
                    -not ($AllowUnresolved -and $vaultName -match '\[[A-Za-z][A-Za-z0-9_.]*\.')) {
                    return $result.LogCritical('Storage v2 Vault name is invalid.')
                }
                if (-not $AllowUnresolved -or
                    ($address -notmatch '\[[A-Za-z][A-Za-z0-9_.]*\.' -and
                     $vaultName -notmatch '\[[A-Za-z][A-Za-z0-9_.]*\.')) {
                    $uri = $null
                    if (-not [uri]::TryCreate([string]$address, [UriKind]::Absolute, [ref]$uri) -or
                        $uri.Scheme -cne 'https' -or $uri.AbsolutePath.Trim('/') -ne '' -or
                        $uri.Host -ine "$vaultName.vault.azure.net") {
                        return $result.LogCritical('Storage v2 Vault route does not match its Resource.')
                    }
                }
            }
        }
        elseif ((& $has $value 'Resource') -or (& $has $route 'ResourceKey')) {
            return $result.LogCritical('Storage v2 filesystem Route must not reference a Resource.')
        }

        # Clone only the v2 jacket. The source object and its token expressions remain intact.
        $copy = $value | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json -Depth 100
        $copy.PSObject.Properties.Remove('Routes')
        $copy.PSObject.Properties.Remove('SchemaVersion')
        $copy | Add-Member -NotePropertyName Addresses -NotePropertyValue @((& $get $route 'Address'))
        if ($Family -in @('AzureStorageAccount','AzureKeyVault')) {
            $copy.PSObject.Properties.Remove('Resource')
            $copy | Add-Member -NotePropertyName Resource -NotePropertyValue (& $get $resources[0] $resourceField)
        }
        $result.SetResult($copy)
    }
    catch {
        $result.LogCritical('Storage v2 jacket could not be resolved.') | Out-Null
    }
    return $result
}
