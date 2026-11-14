function Invoke-TestGraph {
    param (
        [Parameter(Mandatory = $true)]
        [object]$Environment
    )

    # ░▒▓█ INITIALIZE GRAPH █▓▒░
    $graphSignal = [Graph]::Start("Invoke-TestGraph", $opSignal, $true) | Select-Object -Last 1

    $graph = $graphSignal.GetResult()
    $graph.Start()

    # ░▒▓█ DEFINE PATHS █▓▒░
    $relativePath = "SovereignTrust.Adapters\Src\Network\AzureStorageQueue\PowerShell\SovereignTrust.Adapters.Network_AzureStorageQueue.Dependencies.json"
    $rootFolder   = "C:\GitHub\SiliconDreamArtists"
    $fullPath     = Join-Path $rootFolder $relativePath

    # ░▒▓█ BUILD POINTER JACKET █▓▒░
    $pointerJacket = @{
        FullPath    = $fullPath
        VirtualPath = "SovereignTrust.Adapters.Network_AzureStorageQueue.Dependencies"
        Type        = "DependencyGraph"
    }

    # ░▒▓█ CREATE SIGNAL █▓▒░
    $depSignal = [Signal]::Start("Dependencies") | Select-Object -Last 1
    $depSignal.SetPointer($pointerJacket)

    # ░▒▓█ LOAD JSON MEMORY INTO SIGNAL █▓▒░
    $jsonSignal = Get-JsonObjectFromFile -RootFolder $rootFolder -VirtualPath $relativePath | Select-Object -Last 1
    if ($depSignal.MergeSignalAndVerifySuccess($jsonSignal)) {
        $depSignal.SetResult($jsonSignal.GetResult())
        $depSignal.LogInformation("✅ JSON memory loaded and set into Dependencies signal.")
    } else {
        $depSignal.LogCritical("❌ Failed to load JSON for Dependencies.")
    }

    # ░▒▓█ REGISTER INTO GRAPH █▓▒░
    $graph.RegisterSignal("Dependencies", $depSignal)
    $graph.GraphSignal.LogInformation("✅ Dependencies signal registered into graph.")
    $graph.Finalize()

    return $graph
}

function Test-Graph2 {
    param (
        [Parameter(Mandatory = $true)]
        [object]$Graph
    )
    $a = Resolve-PathFromDictionary -Dictionary $graph -Path "Dependencies" | Select-Object -Last 1
    $b1 = Resolve-PathFromDictionary -Dictionary $graph -Path "Dependencies.Module" | Select-Object -Last 1
    $b11 = Resolve-PathFromDictionary -Dictionary $graph -Path "Dependencies.*.VirtualPath" | Select-Object -Last 1
    $b2 = Resolve-PathFromDictionary -Dictionary $graph -Path "Dependencies.Module.Name" | Select-Object -Last 1
    $b3 = Resolve-PathFromDictionary -Dictionary $graph -Path "Dependencies.Classes.Network_AzureStorageQueue" | Select-Object -Last 1
    $b4 = Resolve-PathFromDictionary -Dictionary $graph -Path "Dependencies.Classes.Network_AzureStorageQueue.Source" | Select-Object -Last 1
    $b4 = Resolve-PathFromDictionary -Dictionary $graph -Path "Dependencies.Classes.Network_AzureStorageQueue.Source" | Select-Object -Last 1

    return $graph
}
