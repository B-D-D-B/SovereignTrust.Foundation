function Invoke-PlanPhase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Signal]$ConductionSignal,
        [Parameter(Mandatory)][Signal]$ItemSignal,
        [Parameter(Mandatory)][object]$Phase,
        [string[]]$ReturnKeys = @()
    )

    $opSignal = [Signal]::Start('Invoke-PlanPhase', $ItemSignal) | Select-Object -Last 1
    try {
        $phaseSignal = Invoke-CondenserAdapter `
            -Slot 'Memory' `
            -Activity 'Generate' `
            -Signal $ConductionSignal `
            -Plan $Phase `
            -ItemSignal $ItemSignal |
            Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure($phaseSignal)) { return $opSignal }

        $graph = $ItemSignal.GetPointer()
        if ($graph -isnot [Graph]) {
            throw 'Phase ItemSignal does not have a Graph pointer.'
        }

        $exports = foreach ($key in @($ReturnKeys)) {
            if (-not $graph.Grid.Contains([string]$key)) {
                throw "Requested phase return key '$key' was not registered."
            }
            $resultSignal = $graph.Grid[[string]$key]
            [PSCustomObject]@{
                Key       = [string]$key
                Name      = [string]$resultSignal.Name
                Meta      = $resultSignal.Meta
                HasResult = $resultSignal.HasResult()
                Result    = if ($resultSignal.HasResult()) { $resultSignal.GetResult() } else { $null }
            }
        }

        $opSignal.SetResult([PSCustomObject]@{
            Completed       = $true
            ExportedResults = @($exports)
        })
    }
    catch {
        $null = $opSignal.LogCritical("Phase execution failed: $($_.Exception.Message)", $null, $_)
    }
    return $opSignal
}
