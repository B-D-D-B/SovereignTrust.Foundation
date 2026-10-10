
function Resolve-PathGraphTokenAdapter {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Conductor
    )

    $opSignal = [Signal]::Start("Resolve-PathGraph:TokenAdapter") | Select-Object -Last 1

    # ░▒▓█ RESOLVE REQUIRED CONTEXT █▓▒░
    $pointerSignal = Resolve-PathFromDictionary -Dictionary $Conductor -Path "$.*.#.Adapters.*" | Select-Object -Last 1
    $adapterSignal = Resolve-PathFromDictionary -Dictionary $Conductor -Path "$.*.#.Adapters.*.#.MappedToken" | Select-Object -Last 1

    if ($opSignal.MergeSignalAndVerifyFailure(@($pointerSignal, $adapterSignal))) {
        $opSignal.LogCritical("Unable to resolve required context from Conductor.")
        return $opSignal
    }

    $mappedAdapter = $adapterSignal.GetResult() | Select-Object -Last 1
    if ($mappedAdapter -is [Signal]) {
        $mappedAdapter = $mappedAdapter.GetResult() | Select-Object -Last 1
    }

    #$graphSignalx = Add-PathToDictionary -Dictionary $mappedAdapter -Path "*.#.MappedTokenAdapter" -Value $graphSignal | Select-Object -Last 1
    try {
        # ░▒▓█ BUILD AND POPULATE CONDENSER GRAPH █▓▒░
        $graphSignal = [Graph]::Start("MappedTokenAdapter.Graph", $Conductor, $false) | Select-Object -Last 1
        $graph = $graphSignal.GetResult() | Select-Object -Last 1

        $graph.RegisterResultAsSignal("Dynamic",     [Token_Dynamic]::Start($mappedAdapter, $Conductor))     | Out-Null
        $graph.RegisterResultAsSignal("System",     [Token_System]::Start($mappedAdapter, $Conductor))     | Out-Null
        $graph.RegisterResultAsSignal("Memory",     [Token_Memory]::Start($mappedAdapter, $Conductor))     | Out-Null
        $graph.RegisterResultAsSignal("Storage",       [Token_Storage]::Start($mappedAdapter, $Conductor))       | Out-Null
        $graph.RegisterResultAsSignal("Environment",     [Token_Environment]::Start($mappedAdapter, $Conductor))     | Out-Null
        $graph.RegisterResultAsSignal("Navigator",       [Token_Navigator]::Start($mappedAdapter, $Conductor))       | Out-Null
        $graph.RegisterResultAsSignal("Formatter",     [Token_Formatter]::Start($mappedAdapter, $Conductor))     | Out-Null
        $graph.RegisterResultAsSignal("Conduction",     [Token_Conduction]::Start($mappedAdapter, $Conductor))     | Out-Null
        $graph.RegisterResultAsSignal("Generator",     [Token_Generator]::Start($mappedAdapter, $Conductor))     | Out-Null

        $graph.Finalize()
        $opSignal.SetResult($graph)

        $mappedAdapter.Signal.SetPointer($graphSignal)
        $opSignal.LogInformation("✅ Token formula graph created and populated with condenser adapters.")
    }
    catch {
        $opSignal.LogCritical("🔥 Exception while building condenser graph: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}
