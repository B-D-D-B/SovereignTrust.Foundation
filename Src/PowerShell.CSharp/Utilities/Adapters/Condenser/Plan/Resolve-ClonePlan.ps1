function Resolve-ClonePlan {
    param (
        [object]$Plan
    )

    $opSignal = [Signal]::Start("Resolve-ClonePlan") | Select-Object -Last 1

    $conductionPlan = $null
    $conductionPhase = $null

    try {
        $conductionPlanSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Plan" -SignalLevel "Information" | Select-Object -Last 1
        $conductionPhaseSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Phase" -SignalLevel "Information" | Select-Object -Last 1

        if ($conductionPlanSignal.HasResult()) {
            $conductionPlan = $conductionPlanSignal.GetResult()
            Remove-PathFromDictionary -Dictionary $Plan -Path "Plan" | Select-Object -Last 1
        }

        if ($conductionPhaseSignal.HasResult()) {
            $conductionPhase = $conductionPhaseSignal.GetResult()
            Remove-PathFromDictionary -Dictionary $Plan -Path "Phase" | Select-Object -Last 1
        }

        $clonePlan = $Plan | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100

        if ($conductionPlanSignal.HasResult()) {
            Add-PathToDictionary -Dictionary $Plan -Path "Plan" -Value $conductionPlan | Select-Object -Last 1
            Add-PathToDictionary -Dictionary $clonePlan -Path "Plan" -Value $conductionPlan | Select-Object -Last 1
        }

        if ($conductionPhaseSignal.HasResult()) {
            Add-PathToDictionary -Dictionary $Plan -Path "Phase" -Value $conductionPhase | Select-Object -Last 1
            Add-PathToDictionary -Dictionary $clonePlan -Path "Phase" -Value $conductionPhase | Select-Object -Last 1
        }

        $opSignal.SetResult($clonePlan)
         
    }
    catch {
        $opSignal.LogCritical("🔥 Unhandled exception in Resolve-ClonePlan: $($_.Exception.Message)")
    }


    return $opSignal
}
