function Invoke-ConductionCondenser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$signal
    )

    # ░▒▓█ SIGNAL START █▓▒░
    $opSignal = [Signal]::Start("Invoke-ConductionCondenser") | Select-Object -Last 1

    try {
        # ░▒▓█ VALIDATE INPUT █▓▒░
    $Config = $Signal.GetResult()

        if ($null -eq $Config) {
            $opSignal.LogCritical("Config is null. Cannot proceed.")
            return $opSignal
        }

        $consdenserPath = "%.*.#.MappedCondenserAdapter.@.#.ConductionCondenser"
        $consdenserSignal = Resolve-PathFromDictionary -Dictionary $Signal -Path $adapterPath | Select-Object -Last 1

        $consdenser = $adapterSignal.GetResult()
        
        # TODO: Place the check for if this should be done in an isolated run
        # ░▒▓█ Run the Conduction Condenser using the Config bits  █▓▒░
        $consdenserIvokeSignal = $consdenser.Invoke($Slot, $ConductionSignal, $Plan) | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($consdenserIvokeSignal)) {
            $opSignal.LogCritical("Conduction consdenser failed.")
            return $opSignal
        }
        else {
            $opSignal.SetResult($consdenserIvokeSignal.GetResult())
        }

        return $opSignal
    }
    catch {
        $opSignal.LogCritical("Exception during conduction condenser run: $($_.Exception.Message)", $null, $_)
        return $opSignal
    }















    
    $JsonBody = $Config.JsonBody 
    $Body = $Config.Body 

    if ($null -eq $Body -and $null -ne $JsonBody) {
        if ($Config.ForceArrayBody) {
            $Body = (, @($JsonBody)) | ConvertTo-Json -Depth 10
        }
        else {
            $Body = $JsonBody | ConvertTo-Json -Depth 10
        }
    }


    $InvokeResult = Invoke-RestApi `
        -Config $Config `
        -Body $Body `
        -Method $Config.Method `
        -Querystring $Config.Querystring `
        -Intention $Config.Intention | Select-Object -Last 1

    if ($InvokeResult -and $InvokeResult.Url) {

        $TelemetryLevel = "VerboseInformation"
        if ($InvokeResult.Url -like "*applicationinsights*") {
            $TelemetryLevel = "Silent"
        }
        Write-TelemetryWrapper -StepConfig $Config -Config @{
            ResourceName         = $InvokeResult.ResourceName
            DurationMs           = $InvokeResult.ElapsedMilliseconds
            RemoteDependencyName = "$($InvokeResult.Method)-RestApi"
            RemoteDependencyType = $InvokeResult.Url
            TelemetryLevel       = $TelemetryLevel
            Success              = $InvokeResult.Success
            TelemetryType        = "Dependency"
            TelemetryDataType    = "RemoteDependencyData"
        }
    } 

    if (-not $InvokeResult.Success)
    {
        
    }

    return $InvokeResult.Response ?? $InvokeResult
}