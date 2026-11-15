function Resolve-RemainingResourceRoutesJacket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Jacket,
        [Parameter(Mandatory)][ValidateSet('AzureApplicationInsights','AzureStorageQueue','AzureDataExplorer','AzureSql','Conduction_ST')][string]$Family,
        [switch]$AllowUnresolved,
        [switch]$ValidateNormalizedV2
    )

    $result = [SignalGraph.Signal]::Start('Resolve-RemainingResourceRoutesJacket') | Select-Object -Last 1
    try {
        $value = if ($Jacket -is [SignalGraph.Signal]) { $Jacket.GetResult($true) } else { $Jacket }
        if ($null -eq $value) { return $result.LogCritical('Adapter jacket is absent.') }
        $get = {
            param($item, [string]$name)
            if ($item -is [System.Collections.IDictionary]) {
                foreach ($key in $item.Keys) { if ([string]$key -ceq $name) { return ,$item[$key] } }
                return $null
            }
            $property = $item.PSObject.Properties | Where-Object Name -CEQ $name | Select-Object -First 1
            if ($null -ne $property) { return ,$property.Value }
            return $null
        }
        $fields = {
            param($item)
            if ($null -eq $item) { return @() }
            if ($item -is [System.Collections.IDictionary]) { return @($item.Keys) }
            return @($item.PSObject.Properties.Name)
        }
        $has = {
            param($item, [string]$name)
            return @(& $fields $item | Where-Object { $_ -ceq $name }).Count -eq 1
        }
        $hasCaseInsensitive = {
            param($item, [string]$name)
            return @(& $fields $item | Where-Object { $_ -ieq $name }).Count -gt 0
        }
        $valid = {
            param($item)
            return $item -is [string] -and -not [string]::IsNullOrWhiteSpace($item) -and
                ($AllowUnresolved -or $item -notmatch '\[[A-Za-z][A-Za-z0-9_.]*\.')
        }
        $sqlValid = {
            param($item)
            return $item -is [string] -and $item -cmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'
        }
        $resourceField = switch ($Family) {
            'AzureApplicationInsights' { 'InstrumentationKey' }
            'AzureStorageQueue' { 'QueuePath' }
            'AzureDataExplorer' { 'Database' }
            'AzureSql' { 'Database' }
            default { $null }
        }
        $resourceKey = switch ($Family) {
            'AzureApplicationInsights' { 'instrumentation' }
            'AzureStorageQueue' { 'queue' }
            'AzureDataExplorer' { 'database' }
            'AzureSql' { 'database' }
            default { $null }
        }
        $expectedRoutes = @('primary')
        if ($Family -eq 'Conduction_ST') { $expectedRoutes = @('source','modules') }
        if ($ValidateNormalizedV2) {
            $addresses = & $get $value 'Addresses'
            if ($addresses -isnot [array] -or $addresses.Count -ne $expectedRoutes.Count -or
                @($addresses | Where-Object { -not (& $valid $_) }).Count -gt 0) {
                return $result.LogCritical('Adapter v2 selected Address is invalid after hydration.')
            }
            if ($null -ne $resourceField) {
                $selectedResource = & $get $value 'Resource'
                if (-not (& $valid $selectedResource) -or ($Family -eq 'AzureSql' -and -not (& $sqlValid $selectedResource))) {
                    return $result.LogCritical('Adapter v2 selected Resource is invalid after hydration.')
                }
            }
            $result.SetResult($value)
            return $result
        }

        $version = & $get $value 'SchemaVersion'
        $hasRoutes = & $has $value 'Routes'
        if (-not (& $hasCaseInsensitive $value 'SchemaVersion') -and
            -not (& $hasCaseInsensitive $value 'Routes') -and ((& $get $value 'Resource') -isnot [array])) {
            $result.SetResult($value)
            return $result
        }
        $reservedNames = @('SchemaVersion','Routes','Addresses','Address','Resource')
        foreach ($name in @(& $fields $value)) {
            foreach ($reserved in $reservedNames) {
                if ([string]$name -ieq $reserved -and [string]$name -cne $reserved) {
                    return $result.LogCritical('Adapter v2 jacket has a wrong-case reserved field.')
                }
            }
        }
        if (($version -isnot [long] -and $version -isnot [int]) -or $version -ne 2 -or -not $hasRoutes -or
            (& $has $value 'Addresses') -or (& $has $value 'Address')) {
            return $result.LogCritical('Adapter v2 jacket has an invalid or mixed envelope.')
        }
        $routes = & $get $value 'Routes'
        if ($routes -isnot [array] -or $routes.Count -ne $expectedRoutes.Count) {
            return $result.LogCritical('Adapter v2 route count is invalid.')
        }
        $addresses = @()
        for ($i = 0; $i -lt $expectedRoutes.Count; $i++) {
            $route = $routes[$i]
            $allowed = if ($null -eq $resourceField) { @('Key','Address') } else { @('Key','Address','ResourceKey') }
            $actual = @(& $fields $route)
            $routeKey = & $get $route 'Key'
            if ($actual.Count -ne $allowed.Count -or @($actual | Where-Object { $_ -cnotin $allowed }).Count -gt 0 -or
                $routeKey -isnot [string] -or $routeKey -cne $expectedRoutes[$i] -or -not (& $valid (& $get $route 'Address'))) {
                return $result.LogCritical('Adapter v2 Route is invalid.')
            }
            $routeResourceKey = & $get $route 'ResourceKey'
            if ($null -ne $resourceField -and ($routeResourceKey -isnot [string] -or $routeResourceKey -cne $resourceKey)) {
                return $result.LogCritical('Adapter v2 Resource reference is invalid.')
            }
            $addresses += (& $get $route 'Address')
        }
        if ($null -eq $resourceField) {
            if (& $has $value 'Resource') { return $result.LogCritical('Adapter v2 Resource is unexpected.') }
        }
        else {
            $resources = & $get $value 'Resource'
            if ($resources -isnot [array] -or $resources.Count -ne 1) {
                return $result.LogCritical('Adapter v2 Resource is invalid.')
            }
            $actual = @(& $fields $resources[0])
            $selectedKey = & $get $resources[0] 'Key'
            if ($actual.Count -ne 2 -or @($actual | Where-Object { $_ -cnotin @('Key',$resourceField) }).Count -gt 0 -or
                $selectedKey -isnot [string] -or $selectedKey -cne $resourceKey -or -not (& $valid (& $get $resources[0] $resourceField))) {
                return $result.LogCritical('Adapter v2 Resource payload is invalid.')
            }
            if ($Family -eq 'AzureSql' -and -not $AllowUnresolved -and -not (& $sqlValid (& $get $resources[0] $resourceField))) {
                return $result.LogCritical('Adapter v2 SQL database name is invalid.')
            }
            if ($Family -eq 'AzureSql' -and $AllowUnresolved -and
                (& $get $resources[0] $resourceField) -notmatch '\[[A-Za-z][A-Za-z0-9_.]*\.' -and
                -not (& $sqlValid (& $get $resources[0] $resourceField))) {
                return $result.LogCritical('Adapter v2 SQL database name is invalid.')
            }
        }
        $copy = $value | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json -Depth 100
        $copy.PSObject.Properties.Remove('Routes')
        $copy.PSObject.Properties.Remove('SchemaVersion')
        $copy | Add-Member -NotePropertyName Addresses -NotePropertyValue $addresses
        if ($null -ne $resourceField) {
            $copy.PSObject.Properties.Remove('Resource')
            $copy | Add-Member -NotePropertyName Resource -NotePropertyValue (& $get $resources[0] $resourceField)
        }
        $result.SetResult($copy)
    }
    catch {
        $result.LogCritical('Adapter v2 jacket could not be resolved.') | Out-Null
    }
    return $result
}
