function Invoke-PlanIteration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Signal]$ConductionSignal,

        [Parameter(Mandatory)]
        [Signal]$ItemSignal,

        [Parameter(Mandatory)]
        [object]$Plan,

        [AllowNull()]
        [object]$Iteration,

        [Parameter(Mandatory)]
        [int]$IterationIndex,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$IterationName,

        [object[]]$IterationArray
    )

    $opSignal = [Signal]::Start("Invoke-PlanIteration:$IterationIndex", $ItemSignal) | Select-Object -Last 1

    try {
        $cloneSignal = Resolve-ClonePlan -Plan $Plan | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure(@($cloneSignal)) -or -not $cloneSignal.HasResult()) {
            return $opSignal
        }

        $iterationPlan = $cloneSignal.GetResult()
        $iterationPlan.Activity = $Plan.Config.Activity

        $iterationSignal = [Signal]::Start($IterationName, $ItemSignal) | Select-Object -Last 1
        $iterationSignal.SetResult($Iteration)
        $null = $iterationSignal.AddProperty('IterationIndex', $IterationIndex)
        $null = $iterationSignal.AddProperty('IterationArray', @($IterationArray))

        $itemGraph = $ItemSignal.GetPointer()
        if ($itemGraph -isnot [Graph]) {
            $null = $opSignal.LogCritical("Iteration ItemSignal does not have a Graph pointer.")
            return $opSignal
        }

        $registerSignal = $itemGraph.RegisterSignal($IterationName, $iterationSignal) | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure(@($registerSignal))) {
            return $opSignal
        }

        $adapterParts = @([string]$Plan.Adapter -split '\.')
        if ($adapterParts.Count -lt 2 -or [string]::IsNullOrWhiteSpace($adapterParts[1])) {
            $null = $opSignal.LogCritical("Iteration plan Adapter '$($Plan.Adapter)' does not contain a condenser slot.")
            return $opSignal
        }

        $iterationResultSignal = Invoke-CondenserAdapter `
            -Slot $adapterParts[1] `
            -Activity $Plan.Config.Activity `
            -Plan $iterationPlan `
            -Signal $ConductionSignal `
            -ItemSignal $ItemSignal `
        | Select-Object -Last 1

        $null = $opSignal.MergeSignalAndVerifyFailure(@($iterationResultSignal))
        $opSignal.SetResult([PSCustomObject]@{
            Index        = $IterationIndex
            Iteration    = $Iteration
            ResultSignal = $iterationResultSignal
        })
    }
    catch {
        $null = $opSignal.LogCritical("Iteration $IterationIndex failed: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}
