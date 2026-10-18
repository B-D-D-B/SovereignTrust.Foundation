function Invoke-RestCondenserCore {
    [CmdletBinding()]
    param (
        [RestCondenser]$RestCondenser,

        [string]$Activity, 
        [string]$Slot,
        # Conduction Signal
        [Parameter(Mandatory)]
        [Signal]$Signal,

        # Phase Set Signal (contains array of Phase ItemSignals or phase objects)
        [Parameter(Mandatory)]
        [Signal]$ItemSignal,

        # Full plan object
        [Parameter(Mandatory)]
        [object]$Plan
    )

    $opSignal = [Signal]::Start("Invoke-RestCondenserCore", $ItemSignal) | Select-Object -Last 1

    # Build headers based on if there's a body to send.
    $headers = @{
    }

    if ($null -eq $Body -and $null -ne $JsonBody) {
        $Body = $JsonBody | ConvertTo-Json -Depth 10
    }

    #$context = Resolve-PathFromDictionary -Dictionary $Config -Path "Context" | Select-Object -Last 1
    $retry = $true
    $attempts = 0
    $maxAttempts = 2
    $statusModeAuthRefreshes = 0
    $response = $null
    $targetPathProvided = $null -ne $Plan.Config -and $null -ne $Plan.Config.PSObject.Properties['TargetPath']
    $targetPath = $null
    $targetTempPath = $null
    $targetAuthRefreshes = 0
    if ($targetPathProvided) {
        $targetPath = [string]$Plan.Config.TargetPath
        if ([string]::IsNullOrWhiteSpace($targetPath) -or -not [System.IO.Path]::IsPathFullyQualified($targetPath) -or $targetPath -match '^[^:]+::') {
            return $opSignal.LogCritical('Config.TargetPath must be a nonempty absolute filesystem path.')
        }
        try {
            $targetPath = [System.IO.Path]::GetFullPath($targetPath)
        }
        catch {
            return $opSignal.LogCritical("Config.TargetPath is not a valid filesystem path: $($_.Exception.Message)", $null, $_)
        }
        if ([bool]$Plan.Config.ReturnHttpStatus -or [string]$Plan.Config.Method -ine 'Get' -or
            $null -ne $Plan.Config.SourcePath -or $null -ne $Plan.Config.Body -or $null -ne $Plan.Config.Form) {
            return $opSignal.LogCritical('Config.TargetPath requires a GET without status or request body options.')
        }
    }
    while ($retry) {
        $sw = [System.Diagnostics.Stopwatch]::new() 
        try {
            $QuerystringSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Querystring" -Default "" -SignalLevel "Information" | Select-Object -Last 1
            $HeadersSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Headers" -Default $headers | Select-Object -Last 1
            $UriSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Uri" | Select-Object -Last 1
            $BearerTokenSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.BearerToken" -Default $null | Select-Object -Last 1
            $MethodSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Method" -Default $null | Select-Object -Last 1
            $returnHttpStatusSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.ReturnHttpStatus" -Default $false | Select-Object -Last 1
            $ContentTypeSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.ContentType" -Default $null | Select-Object -Last 1
            $InFileSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.SourcePath" -Default $null | Select-Object -Last 1

            # TODO: This should be done in ItemSignal instead of Config.Body
            $BodySignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Body" -Default $null | Select-Object -Last 1
            $FormSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.Form" -Default $null | Select-Object -Last 1

            $Url = $UriSignal.GetResult()
            # Strip Url from array if in an array.
            $Url = (@($Url))[0]

            $Token = $BearerTokenSignal.HasResult() ? $BearerTokenSignal.GetResult() : $null
            $Querystring = $QuerystringSignal.HasResult() ? $QuerystringSignal.GetResult() : $null
            $headers = $HeadersSignal.HasResult() ? $HeadersSignal.GetResult() : $null

            $Body = $BodySignal.HasResult() ? $BodySignal.GetResult() : $null
            $Form = $FormSignal.HasResult() ? $FormSignal.GetResult() : $null
            $Method = $MethodSignal.HasResult() ? $MethodSignal.GetResult() : $null
            $returnHttpStatus = [bool]$returnHttpStatusSignal.GetResult()
            $httpStatus = $null
            $responseHeaders = $null
            $ContentType = $ContentTypeSignal.HasResult() ? $ContentTypeSignal.GetResult() : $null
            $InFile = $InFileSignal.HasResult() ? $InFileSignal.GetResult() : $null
            if ($Body -and ($Body -isnot [string])) {
                $Body = $Body | ConvertTo-Json -Depth 100
            }

            if ($headers -is [PSCustomObject]) {
                $_headers = @{}
                foreach ($property in $headers.PSObject.Properties) {
                    $_headers[$property.Name] = $property.Value
                }

                $headers = $_headers
            }

            if ($Token) {
                $headers["Authorization"] = "Bearer $Token"
            }

            $FinalUrl = $Url
            if ($null -ne $Querystring -and $Querystring -ne "" -and $Url -notlike "*$Querystring") {
                $FinalUrl = $Url + $Querystring
            }

            $sw.Start()
            if ($Null -ne $InFile) {
                if (-not $Method) {
                    $Method = "Put"
                }

                Invoke-RestMethod `
                    -Uri $FinalUrl `
                    -Method $Method `
                    -Headers $headers `
                    -ContentType $ContentType `
                    -InFile $InFile            
            }
            elseif ($null -ne $Body) {
                if (-not $Method) {
                    $Method = "Post"
                }

                # TODO: Do Externally and pass in through config.
                if ($Body) {
                    if ($ContentType) {
                        $headers["Content-Type"] = $ContentType
                    }
                    else {
                        $headers["Content-Type"] = "application/json; charset=utf-8"
                        $headers["Accept"] = "application/json"
                    }
                }

                $response = Invoke-RestMethod -Uri $FinalUrl -Method $Method -Headers $headers -Body $Body
            }
            elseif ($Form) {
                $_form = @{}

                foreach ($property in $Form.PSObject.Properties) {
                    $name = $property.Name
                    $value = $property.Value

                    if (Test-Path $value -PathType Leaf) {
                        $_form[$name] = (Get-Item $value)
                    }
                    else {
                        $_form[$name] = $value
                    }
                }
                $response = Invoke-RestMethod -Uri $FinalUrl -Method $Method -Headers $headers -Form $_form
            }
            else {
                if (-not $Method) {
                    $Method = "get"
                }
                
                if ($targetPathProvided) {
                    $targetDirectory = [System.IO.Path]::GetDirectoryName($targetPath)
                    [System.IO.Directory]::CreateDirectory($targetDirectory) | Out-Null
                    $targetTempPath = [System.IO.Path]::Combine($targetDirectory, '.st-read-' + [guid]::NewGuid().ToString('N') + '.tmp')
                    $null = Invoke-RestMethod -Uri $FinalUrl -Method $Method -Headers $headers -OutFile $targetTempPath
                    if (-not [System.IO.File]::Exists($targetTempPath)) { throw 'REST GET did not create the target file.' }
                    [System.IO.File]::Move($targetTempPath, $targetPath, $true)
                    $targetTempPath = $null
                    $response = $targetPath
                }
                elseif ($returnHttpStatus) {
                    $response = Invoke-RestMethod -Uri $FinalUrl -Method $Method -Headers $headers -SkipHttpErrorCheck -StatusCodeVariable httpStatus -ResponseHeadersVariable responseHeaders
                    if ([int]$httpStatus -eq 401) {
                        throw '401 (Unauthorized)'
                    }
                }
                else {
                    $response = Invoke-RestMethod -Uri $FinalUrl -Method $Method -Headers $headers
                }
            }
        
            if ($sw.IsRunning) { $sw.Stop() }

            $opSignal.LogInformation("Rest $Method Successful against $FinalUrl", @("Verbose"))
            $result = @{
                Response            = $Response
                Url                 = $FinalUrl
                Method              = $Method
                ResourceName        = $ResourceName
                Success             = $true
                StatusCode          = $httpStatus
                Headers             = $responseHeaders
                ElapsedMilliseconds = $sw.ElapsedMilliseconds
            }

            $opSignal.SetResult($result)
            return $opSignal
        }
        catch {
            if ($sw.IsRunning) { $sw.Stop() }
            if ($targetTempPath -and [System.IO.File]::Exists($targetTempPath)) { [System.IO.File]::Delete($targetTempPath) }
            $targetTempPath = $null
            $attempts++
            $message = $_.ErrorDetails.Message ?? $_.Exception.Message

            # Change this so that this sends the details back to the prior level in the $opSignal to alert it that a failure has happened and this is how you heal it. (ClearBearerToken)
            if ($message -like "*token is expired*" -or $message -like "*401 (Unauthorized)*" -or $message -like "*authenticate header*") {
                if ($returnHttpStatus -or $targetPathProvided) {
                    if ($targetPathProvided -and $targetAuthRefreshes -ge 1) {
                        return $opSignal.LogCritical("Authentication still failed after token refresh for '$FinalUrl'.", $null, $_)
                    }
                    if ($targetPathProvided) { $targetAuthRefreshes++ }
                    if ($statusModeAuthRefreshes -ge 1) {
                        $opSignal.LogCritical("Authentication still failed after token refresh for '$FinalUrl'.", $null, $_)
                        return $opSignal
                    }
                    $statusModeAuthRefreshes++
                }
                #clearBearerToken = $true
                $skipBearerTokenSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.SkipBearerToken" -Default $false | Select-Object -Last 1
                $bearerTokenSignal = $skipBearerTokenSignal.GetResult() ? $null : $RestCondenser.ResolveBearerToken($Signal, $Plan, $true)
                if ($bearerTokenSignal -and $bearerTokenSignal.HasResult()) {
                    $null = Add-PathToDictionary -Dictionary $Plan -Path "Config.BearerToken" -Value $bearerTokenSignal.GetResult()
                    if (-not $targetPathProvided) { $attempts = 0 }
                }
                else {
                    $opSignal.LogCritical("Failed to refresh bearer token. Cannot retry request to '$FinalUrl'.", $null, $_)
                    return $opSignal
                }
            }
            else {
                #Start-Sleep -Milliseconds 10000
            }

                        # Change this so that this sends the details back to the prior level in the $opSignal to alert it that a failure has happened and this is how you heal it. (ClearBearerToken)
            if ($message -like "*No such host is known*") {
                #clearBearerToken = $true
                $skipBearerTokenSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config.SkipBearerToken" -Default $false | Select-Object -Last 1
                $bearerTokenSignal = $skipBearerTokenSignal.GetResult() ? $null : $RestCondenser.ResolveBearerToken($Signal, $Plan, $true)
                if ($bearerTokenSignal -and $bearerTokenSignal.HasResult()) {
                    $null = Add-PathToDictionary -Dictionary $Plan -Path "Config.BearerToken" -Value $bearerTokenSignal.GetResult()
#                    $attempts = 0
                }
                else {
                    $opSignal.LogCritical("Failed to refresh bearer token. Cannot retry request to '$FinalUrl'.", $null, $_)
                    return $opSignal
                }
            }
            else {
                #Start-Sleep -Milliseconds 10000
            }

            if ($attempts -gt $maxAttempts) {
                $opSignal.LogCritical("Exception during attempt $($attempts) on call to '$FinalUrl' $message", $null, $_)
                return $opSignal
            }

            $opSignal.LogWarning("Attempt $($attempts) Error during call to '$FinalUrl' $message", @("Retry"))
        }
    }
}   
