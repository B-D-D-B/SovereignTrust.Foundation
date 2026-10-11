
function Resolve-PathGraphForPublisher {
    param (
        [Parameter(Mandatory)][string]$WirePath,
        [Parameter()][object]$Environment,
        [Parameter()][string]$RootPath = "m:/sda/Projects-meta"
    )

    $signal = [Signal]::Start("Resolve-PathGraphForSDAPublisher:$WirePath") | Select-Object -Last 1
    $graphSignal = [Graph]::Start("Resolve-PathGraphForSDAPublisher:$WirePath", $opSignal, $true) | Select-Object -Last 1
    $graph = $graphSignal.GetResult()

    $graph.Start()

    $segmentsFull = $WirePath -split '_'
    $segments = $segmentsFull[0] -split '\.'
    $keys = @("Publisher", "Agency", "Project", "Collection", "Series", "Set", "Run", "Artifact", "Author")

    $folderPath = $RootPath
    $virtualPathAccum = ""

    for ($i = 0; $i -lt $segments.Length; $i++) {
        $segment = $segments[$i]
        $virtualPathAccum = if ($virtualPathAccum -eq "") { $segment } else { "$virtualPathAccum.$segment" }
        $levelName = if ($i -lt $keys.Length) { $keys[$i] } else { "Level$i" }

        $folderPath = Join-Path $folderPath $segment
        $fileName = "$virtualPathAccum.json"
        $relativeFilePath = Join-Path $folderPath $fileName
        $fullFolderPath = Convert-Path (Resolve-Path $folderPath -ErrorAction SilentlyContinue) ?? (Join-Path (Get-Location) $folderPath)
        $fullFilePath = Join-Path $fullFolderPath $fileName

        $nodeSignal = [Signal]::new($levelName)
        $nodeSignal.SetResult(@{
            Level              = $i
            Segment            = $segment
            VirtualPath        = $virtualPathAccum
            RelativeFolderPath = $folderPath
            RelativeFilePath   = $relativeFilePath
            FullFolderPath     = $fullFolderPath
            FullFilePath       = $fullFilePath
        })
        $graph.RegisterSignal($levelName, $nodeSignal)
    }

    $graph.Finalize()
    $signal.SetResult($graph)
    $signal.LogInformation("✅ Graph for SDA publishing path structure resolved.")
    return $signal
}
