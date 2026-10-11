function Resolve-RegisteredAdapter {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Registration,

        [Parameter(Mandatory)]
        [Signal]$Signal,

        [Parameter(Mandatory)]
        [object]$ConductionContext
    )

    $opSignal = [Signal]::Start('Resolve-RegisteredAdapter', $Signal) | Select-Object -Last 1

    if ($null -eq $Registration -or -not [bool]$Registration.IsAdapterRegistration) {
        $opSignal.SetResult($Registration)
        return $opSignal
    }

    $lockTaken = $false
    try {
        [System.Threading.Monitor]::Enter($Registration.SyncRoot, [ref]$lockTaken)

        if ($null -ne $Registration.Instance) {
            $opSignal.SetResult($Registration.Instance)
            return $opSignal
        }

        if ($Registration.State -eq 'Resolving') {
            $null = $opSignal.LogCritical(
                "Circular lazy-adapter dependency detected for '$($Registration.Kind).$($Registration.Slot)'."
            )
            return $opSignal
        }

        if ($Registration.State -eq 'Failed' -and -not [bool]$Registration.RetryFailedResolution) {
            $null = $opSignal.LogCritical(
                "Lazy adapter '$($Registration.Kind).$($Registration.Slot)' previously failed: $($Registration.LastError)"
            )
            return $opSignal
        }

        $Registration.State = 'Resolving'
        $resolutionContext = if ($null -ne $Registration.ConductionContext) {
            $Registration.ConductionContext
        }
        else {
            $ConductionContext
        }
        $resolveSignal = Resolve-AdapterFromJacket `
            -Signal $Signal `
            -ConductionContext $resolutionContext `
            -Jacket $Registration.Jacket `
        | Select-Object -Last 1

        if ($resolveSignal.Failure() -or -not $resolveSignal.HasResult()) {
            $Registration.State = 'Failed'
            $Registration.LastError = if ($resolveSignal.Failure()) {
                "Adapter resolution returned a critical signal."
            }
            else {
                "Adapter resolution returned no instance."
            }
            $null = $opSignal.MergeSignal($resolveSignal)
            if (-not $opSignal.Failure()) {
                $null = $opSignal.LogCritical($Registration.LastError)
            }
            return $opSignal
        }

        $Registration.Instance = $resolveSignal.GetResult()
        $Registration.State = 'Resolved'
        $Registration.LastError = $null
        $null = $opSignal.MergeSignal($resolveSignal)
        $opSignal.SetResult($Registration.Instance)
    }
    catch {
        $Registration.State = 'Failed'
        $Registration.LastError = $_.Exception.Message
        $null = $opSignal.LogCritical(
            "Failed to resolve lazy adapter '$($Registration.Kind).$($Registration.Slot)': $($_.Exception.Message)",
            $null,
            $_
        )
    }
    finally {
        if ($lockTaken) {
            [System.Threading.Monitor]::Exit($Registration.SyncRoot)
        }
    }

    return $opSignal
}
