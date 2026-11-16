function Invoke-PlanIteration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [SignalGraph.Signal]$ConductionSignal,

        [Parameter(Mandatory)]
        [SignalGraph.Signal]$ItemSignal,

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

    $stIteration = $null
    if($null -ne $script:STExecutionTraceState){
        $stIteration=@{IterationTemplateId='Plan/'+$Plan.Name;IterationIndex=$IterationIndex;IterationKey=[string]$IterationIndex;Cardinality=@($IterationArray).Count;InputSetSha256=(Get-STExecutionTraceInputHash @('Plan:'+ $Plan.Name,'Count:'+ @($IterationArray).Count))}
    }
    $stTrace = Enter-STExecutionTrace -BoundaryKind 'PlanIteration' -Name $IterationName -Adapter ([string]$Plan.Adapter) -Activity ([string]$Plan.Config.Activity) -Iteration $stIteration
    $stThrew=$false
    $stFailureFrame=New-STFailureFrame $Plan $ConductionSignal 'Iteration' ([string]$Plan.Adapter) ([string]$Plan.Config.Activity)
    $stFailureFrame.IterationIndex=$IterationIndex
    $stFailureFrame.IterationName=Get-STFailureScalar $IterationName
    $opSignal = [SignalGraph.Signal]::Start("Invoke-PlanIteration:$IterationIndex", $ItemSignal) | Select-Object -Last 1

    try {
        $cloneSignal = Resolve-ClonePlan -Plan $Plan | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure(@($cloneSignal)) -or -not $cloneSignal.HasResult()) {
            return $opSignal
        }

        $iterationPlan = $cloneSignal.GetResult()
        Copy-STFailureNodeOwnership $Plan $iterationPlan
        $null=Set-STFailureNodeContext $iterationPlan $stFailureFrame $ConductionSignal.Id -ReplaceVerified
        $iterationPlan.Activity = $Plan.Config.Activity

        $iterationSignal = [SignalGraph.Signal]::Start($IterationName, $ItemSignal) | Select-Object -Last 1
        $iterationSignal.SetResult($Iteration)
        $null = $iterationSignal.AddProperty('IterationIndex', $IterationIndex)
        $null = $iterationSignal.AddProperty('IterationArray', @($IterationArray))

        $itemGraph = $ItemSignal.GetPointer()
        if ($itemGraph -isnot [SignalGraph.Graph]) {
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
        $stThrew=$true
        $null = $opSignal.LogCritical("Iteration $IterationIndex failed: $($_.Exception.Message)", $null, $_.Exception)
    }
    finally { Add-STFailureBoundary $opSignal $stFailureFrame $ConductionSignal.Id; Exit-STExecutionTrace $stTrace $opSignal $stThrew }

    return $opSignal
}
