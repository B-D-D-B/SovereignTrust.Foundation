
function Convert-JsonToGraph {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Json,

        [Parameter()]
        [bool]$IgnoreInternalObjects = $false
    )

    $signal = [Signal]::Start("Convert-JsonToGraph") | Select-Object -Last 1

    try {
        $parsed = $Json | ConvertFrom-Json -Depth 25
        $graph = [Graph]::Start("Convert-JsonToGraph")

        if (-not $IgnoreInternalObjects -and $parsed.GraphSignal) {
            $graph.GraphSignal = [Signal]::FromJson(($parsed.GraphSignal | ConvertTo-Json -Depth 25))
        }

        foreach ($key in $parsed.Grid.PSObject.Properties.Name) {
            $entry = $parsed.Grid[$key]
            $signalObj = if ($IgnoreInternalObjects) {
                $sig = [Signal]::new($key)
                $sig.SetResult($entry)
                $sig
            } else {
                [Signal]::FromJson(($entry | ConvertTo-Json -Depth 25))
            }

            $graph.RegisterNewSignal($key, $signalObj)
        }

        $graph.Finalize()
        $signal.SetResult($graph)
        $signal.LogInformation("✅ Graph successfully reconstructed from JSON.")
    }
    catch {
        $signal.LogCritical("🔥 Exception: Failed to convert JSON to Graph: $($_.Exception.Message)", $null, $_)
    }

    return $signal
}
