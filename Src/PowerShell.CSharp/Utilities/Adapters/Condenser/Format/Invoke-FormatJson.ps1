function Invoke-FormatJson {
    param (
        [Parameter(Mandatory)]$Path,
        [object]$Plan
    )

    $opSignal = [Signal]::Start("Invoke-TokenFormatterJson") | Select-Object -Last 1

    try {

        $formatSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Format" -Default "Json" | Select-Object -Last 1
        $format = $formatSignal.GetResult()

        switch ($format) {
            "Json" {
                $json = $Path | ConvertFrom-Json -Depth 100 
                $opSignal.SetResult($json)
                break
            }
            "JsonArray" {
                $obj = @()
                foreach ($item in @($Path)) {
                    $json = $item | ConvertFrom-Json -Depth 100 
                    $obj += $json
                }
                $opSignal.SetResult($obj)
                break
            }
        }
        

        $opSignal.LogInformation("✅ Json Created from Path")
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Invoke-TokenFormatterJson: $_", $null, $_)
    }
 
    return $opSignal
}
