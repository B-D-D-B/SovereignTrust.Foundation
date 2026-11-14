#TODO: Make Signal Doctrine Compliant
function Resolve-FilteredArrayItem {
    param (
        [Parameter(Mandatory)] $Array,
        [Parameter(Mandatory)] $Filters,
        [Parameter()] $Signal = $null
    )

    foreach ($item in $Array) {
        $matched = $true

        foreach ($filter in $Filters) {
            $lhs = if ($item -is [pscustomobject]) {
                $item."$($filter.Key)"
            } else {
                $item[$filter.Key]
            }

            $rhs = $filter.Value
            $op  = $filter.Op

            $comparison = switch ($op) {
                '-eq'   { $lhs -eq $rhs }
                '-ne'   { $lhs -ne $rhs }
                '-like' { $lhs -like $rhs }
                '-ilike'{ $lhs -ilike $rhs }
                default {
                    if ($null -ne $Signal) {
                        $Signal.LogWarning("Unknown comparison operator '$op'.")
                    }
                    $false
                }
            }

            if (-not $comparison) {
                $matched = $false
                break
            }
        }

        if ($matched) {
            return $item
        }
    }

    if ($null -ne $Signal) {
        $Signal.LogWarning("Filtered array match failed. No item satisfied all conditions.")
    }

    return $null
}
