
function Convert-GraphToJson {
    param (
        [Parameter(Mandatory = $true)]
        [Graph]$Graph,

        [Parameter()]
        [bool]$IgnoreInternalObjects = $false
    )

    $signal = [Signal]::Start("Convert-GraphToJson") | Select-Object -Last 1

    try {
        $exportObject = @{
            Environment = if ($IgnoreInternalObjects) { $null } else { $Graph.Environment }
            GraphSignal = if ($IgnoreInternalObjects) { $null } else { $Graph.GraphSignal }
            Grid  = @{}
        }

        foreach ($key in $Graph.Grid.Keys) {
            $sig = $Graph.Grid[$key]
            $exportObject.Grid[$key] = if ($IgnoreInternalObjects) {
                $sig.Result  # Only export signal result, skip logs/pointers
            } else {
                $sig
            }
        }

        $json = $exportObject | ConvertTo-Json -Depth 25
        $signal.SetResult($json)
        $signal.LogInformation("✅ Graph successfully serialized into JSON.")
    }
    catch {
        $signal.LogCritical("🔥 Exception: Failed to convert Graph to JSON: $($_.Exception.Message)", $null, $_)
    }

    return $signal
}
