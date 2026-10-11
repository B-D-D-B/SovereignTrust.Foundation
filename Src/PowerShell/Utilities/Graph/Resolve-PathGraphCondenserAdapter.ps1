
function Resolve-PathGraphCondenserAdapter {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Conductor
    )

    $opSignal = [Signal]::Start("Resolve-PathGraph:CondenserAdapter") | Select-Object -Last 1

    # ░▒▓█ RESOLVE REQUIRED CONTEXT █▓▒░
    $pointerSignal = Resolve-PathFromDictionary -Dictionary $Conductor -Path "$.*.#.Adapters.*" | Select-Object -Last 1
    $adapterSignal = Resolve-PathFromDictionary -Dictionary $Conductor -Path "$.*.#.Adapters.*.#.MappedCondenser" | Select-Object -Last 1

    if ($opSignal.MergeSignalAndVerifyFailure(@($pointerSignal, $adapterSignal))) {
        $opSignal.LogCritical("Unable to resolve required context from Conductor.")
        return $opSignal
    }

    $mappedAdapter = $adapterSignal.GetResult() | Select-Object -Last 1
    if ($mappedAdapter -is [Signal]) {
        $mappedAdapter = $mappedAdapter.GetResult() | Select-Object -Last 1
    }

    #$graphSignalx = Add-PathToDictionary -Dictionary $mappedAdapter -Path "*.#.MappedCondenserAdapter" -Value $graphSignal | Select-Object -Last 1
    try {
        # ░▒▓█ BUILD AND POPULATE CONDENSER GRAPH █▓▒░
        $graphSignal = [Graph]::Start("MappedCondenserAdapter.Graph", $Conductor, $false) | Select-Object -Last 1
        $graph = $graphSignal.GetResult() | Select-Object -Last 1

        $graph.RegisterResultAsSignal("FabCondenser",       [FabCondenser]::Start($mappedAdapter, $Conductor))       | Out-Null
        $graph.RegisterResultAsSignal("RestCondenser",       [RestCondenser]::Start($mappedAdapter, $Conductor))       | Out-Null
        $graph.RegisterResultAsSignal("FormatCondenser",       [FormatCondenser]::Start($mappedAdapter, $Conductor))       | Out-Null
        $graph.RegisterResultAsSignal("MergeCondenser",     [MergeCondenser]::Start($mappedAdapter, $Conductor))     | Out-Null
        $graph.RegisterResultAsSignal("MapCondenser",       [MapCondenser]::Start($mappedAdapter, $Conductor))       | Out-Null
        $graph.RegisterResultAsSignal("TokenCondenser",     [TokenCondenser]::Start($mappedAdapter, $Conductor))     | Out-Null
        $graph.RegisterResultAsSignal("PlanCondenser",     [PlanCondenser]::Start($mappedAdapter, $Conductor))     | Out-Null
#        $graph.RegisterResultAsSignal("GlobalCondenser",     [GlobalCondenser]::Start($mappedAdapter, $Conductor))     | Out-Null
        $graph.RegisterResultAsSignal("HydrationCondenser", [HydrationCondenser]::Start($mappedAdapter, $Conductor)) | Out-Null
        $graph.RegisterResultAsSignal("TransformCondenser", [TransformCondenser]::Start($mappedAdapter, $Conductor)) | Out-Null
#        $graph.RegisterResultAsSignal("GridCondenser",     [GridCondenser]::Start($mappedAdapter, $Conductor))     | Out-Null
        $graph.RegisterResultAsSignal("ConduitCondenser",     [ConduitCondenser]::Start($mappedAdapter, $Conductor))     | Out-Null
        $graph.RegisterResultAsSignal("MemoryCondenser", [MemoryCondenser]::Start($mappedAdapter, $Conductor)) | Out-Null
        $graph.RegisterResultAsSignal("GraphCondenser", [GraphCondenser]::Start($mappedAdapter, $Conductor)) | Out-Null
        $graph.RegisterResultAsSignal("ConductionCondenser", [ConductionCondenser]::Start($mappedAdapter, $Conductor)) | Out-Null

        $graph.Finalize()
        $opSignal.SetResult($graph)
        $opSignal.LogInformation("✅ Condenser formula graph created and populated with condenser adapters.")
    }
    catch {
        $opSignal.LogCritical("🔥 Exception while building condenser graph: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}
