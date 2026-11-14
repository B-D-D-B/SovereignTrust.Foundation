function Resolve-MappedAdapter {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Signal]$AdapterSignal,

        [Parameter(Mandatory)]
        [Signal]$Signal,

        [Parameter(Mandatory)]
        [object]$ConductionContext
    )

    $opSignal = [Signal]::Start('Resolve-MappedAdapter', $Signal) | Select-Object -Last 1
    $registration = $AdapterSignal.GetResult($true)
    $resolveSignal = Resolve-RegisteredAdapter `
        -Registration $registration `
        -Signal $Signal `
        -ConductionContext $ConductionContext `
    | Select-Object -Last 1

    if ($opSignal.MergeSignalAndVerifyFailure($resolveSignal) -or -not $resolveSignal.HasResult()) {
        if (-not $opSignal.Failure()) {
            $null = $opSignal.LogCritical('Mapped adapter resolution returned no instance.')
        }
        return $opSignal
    }

    $instance = $resolveSignal.GetResult()
    if ([bool]$registration.IsAdapterRegistration) {
        $AdapterSignal.SetResult($instance)
    }
    $opSignal.SetResult($instance)
    return $opSignal
}
