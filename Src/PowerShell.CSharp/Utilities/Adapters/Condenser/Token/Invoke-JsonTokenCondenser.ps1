# =============================================================================
# 🚦 Invoke-JsonTokenCondenser
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☚️🐝🤖/ • Neural Alchemist ⚗️☣️🐲 • Version: 2025.5.22
# =============================================================================
# Invokes Conduction phase processing using a sovereign Graph structure and
# interprets each Phase block in sequence or via branching (OnSuccess / OnFail).
# Compatible with the SDA GridCondenser pipeline and sovereign runtime standards.
# =============================================================================

function Invoke-JsonTokenCondenser {
    [CmdletBinding()]
    param (
        [Signal]$Signal,
        [object]$Plan,
        [Signal]$ItemSignal,
        [string]$RegexPattern = "(?s)\[((?>[^\[\]/]|(?<open>\[)|(?<-open>\]))+(?(open)(?!)))\/\]"
    )

    $opSignal = $null

    try {
        $opSignal = [Signal]::Start("Invoke-JsonTokenCondenser", $Signal) | Select-Object -Last 1

        try {
            $sourceContentPathSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Path" | Select-Object -Last 1
        }
        catch {
            $opSignal.LogCritical("Invoke-JsonTokenCondenser failed while resolving plan Path. $($_.Exception.Message)")
            return $opSignal
        }

        if ($opSignal.MergeSignalAndVerifyFailure($sourceContentPathSignal)) { return $opSignal }

        try {
            $HydrationStyleSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "HydrationStyle" -SignalLevel "Information" | Select-Object -Last 1
        }
        catch {
            $opSignal.LogCritical("Invoke-JsonTokenCondenser failed while resolving HydrationStyle. $($_.Exception.Message)")
            return $opSignal
        }

        if ($opSignal.MergeSignalAndVerifyFailure($HydrationStyleSignal)) { return $opSignal }

        try {
            $HydrationStyle = $HydrationStyleSignal.HasResult() ? $HydrationStyleSignal.GetResult() : $null
        }
        catch {
            $opSignal.LogCritical("Invoke-JsonTokenCondenser failed while reading HydrationStyle result. $($_.Exception.Message)")
            return $opSignal
        }

        try {
            $resultSignal = Resolve-PathFromDictionary -Dictionary $ItemSignal -Path $sourceContentPathSignal.GetResult() | Select-Object -Last 1
        }
        catch {
            $opSignal.LogCritical("Invoke-JsonTokenCondenser failed while resolving source content path. $($_.Exception.Message)")
            return $opSignal
        }

        if ($opSignal.MergeSignalAndVerifyFailure($resultSignal)) { return $opSignal }

        try {
            $result = $resultSignal.GetResult()
        }
        catch {
            $opSignal.LogCritical("Invoke-JsonTokenCondenser failed while reading resolved source content. $($_.Exception.Message)")
            return $opSignal
        }

        if ($HydrationStyle -eq "Deferred") {
            $RegexPattern = "(?s)\[((?>[^\[\]|]|(?<open>\[)|(?<-open>\]))+(?(open)(?!)))\|\]"
        }

        # Stubbed placeholders for testing
        $MergeCondenserFeedback = $opSignal
        $ReturnRequiredValues = $true

        $tokenCrawlIndex = 0
        do {
            $replacementCount = 0

            try {
                $_result = Invoke-TokenCrawl -MergeCondenserFeedback $MergeCondenserFeedback `
                    -Signal $Signal `
                    -ItemSignal $ItemSignal `
                    -Plan $Plan `
                    -CurrentObject $result `
                    -ReturnRequiredValues:$ReturnRequiredValues `
                    -HydrationStyle $HydrationStyle `
                    -RegexPattern $RegexPattern `
                    -ReplacementCount ([ref]$replacementCount) | Select-Object -Last 1
            }
            catch {
                $opSignal.LogCritical("Invoke-JsonTokenCondenser failed during token crawl pass $tokenCrawlIndex. $($_.Exception.Message)")
                return $opSignal
            }

            $tokenCrawlIndex++
        } while ($replacementCount -gt 0)

        #-RegexPattern '^@TKN:'
        #"\[([^\[\]=]+?)/\]"

        try {
            $opSignal.LogInformation("✅ Token Condenser executed.")
            $opSignal.SetResult($result)
        }
        catch {
            $opSignal.LogCritical("Invoke-JsonTokenCondenser failed while finalizing result. $($_.Exception.Message)")
            return $opSignal
        }

        return $opSignal
    }
    catch {
        if ($null -ne $opSignal) {
            $opSignal.LogCritical("Invoke-JsonTokenCondenser failed with an unhandled exception. $($_.Exception.Message)")
            return $opSignal
        }

        throw
    }
}

<# TODO: Fix this not returning an opSignal that is gathering the opSignal results. #>
<# TODO: Invoke-GlobalTokenCrawl is defined twice, it should be genericized for Token #>

function Invoke-TokenCrawl {
    [CmdletBinding()]
    param (
        [Signal]$Signal,
        [object]$Plan,
        [Signal]$ItemSignal,
        [object]$MergeCondenserFeedback,
        [object]$CurrentObject,
        [bool]$ReturnRequiredValues = $true,
        [string]$HydrationStyle = "",
        [string]$RegexPattern,
        [ref]$ReplacementCount
    )

    function Write-TokenCrawlCritical {
        param (
            [object]$Feedback,
            [string]$Message
        )

        throw $Message
        try {
            if ($null -ne $Feedback -and $Feedback.PSObject.Methods.Name -contains "LogCritical") {
                $Feedback.LogCritical($Message)
            }
            elseif ($null -ne $Feedback -and $Feedback.PSObject.Methods.Name -contains "LogWarning") {
                $Feedback.LogWarning($Message)
            }
        }
        catch {
            # Do not let logging failures hide the original failure path.
        }
    }

    function Invoke-ParseJsonString {
        param ([string]$_input)

        try {
            if ([string]::IsNullOrWhiteSpace($_input)) { return $null }

            $trimmed = $_input.Trim()

            try {
                if ($trimmed.StartsWith('Formatter.Json')) {
                    return $_input
                    return $trimmed | ConvertFrom-Json -ErrorAction Stop
                }

                if ($trimmed.StartsWith('{') -and $trimmed.EndsWith('}')) {
                    return $_input
                    return $trimmed | ConvertFrom-Json -ErrorAction Stop
                }
                elseif ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']') -and (-not $trimmed.EndsWith('/]') -and -not $trimmed.EndsWith('|]'))) {
                    return $_input
                    $val = $trimmed | ConvertFrom-Json -ErrorAction Stop
                    return @($val)
                }
            }
            catch {
                return $null
            }

            return $_input
        }
        catch {
            Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Invoke-ParseJsonString failed. $($_.Exception.Message)"
            return $null
        }
    }

    function _ResolveAndDeserializeProperty {
        param (
            [Signal]$Signal,
            [object]$Plan,
            [Signal]$ItemSignal,
            [object]$MergeCondenserFeedback,
            [object]$Parent,
            [string]$Key,
            [bool]$ReturnRequiredValues,
            [string]$RegexPattern,
            [string]$HydrationStyle = ""
        )

        try {
            try {
                $valueSignal = Resolve-PathFromDictionary -Dictionary $Parent -Path $Key | Select-Object -Last 1
            }
            catch {
                Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Failed to resolve path '$Key'. $($_.Exception.Message)"
                return
            }

            try {
                if ($valueSignal.Failure()) {
                    return
                }
            }
            catch {
                Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Failed while checking path resolution result for '$Key'. $($_.Exception.Message)"
                return
            }

            try {
                $propObject = [PSCustomObject]@{ Name = $Key; Value = $valueSignal.GetResult() }
                $originalPropertyValue = $propObject.Value
            }
            catch {
                Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Failed while creating token property object for '$Key'. $($_.Exception.Message)"
                return
            }

            try {
                Resolve-TokenForProperty `
                    -MergeCondenserFeedback $MergeCondenserFeedback `
                    -Property $propObject `
                    -Signal $Signal `
                    -ItemSignal $ItemSignal `
                    -Plan $Plan `
                    -HydrationStyle $HydrationStyle `
                    -RegexPattern $RegexPattern `
                    -ReturnRequiredValues:$ReturnRequiredValues | Select-Object -Last 1 | Out-Null
            }
            catch {
                Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Failed to resolve token for '$Key'. $($_.Exception.Message)"
                return
            }

            try {
                if ($HydrationStyle -eq "" -and $propObject.Value -like '*/]*') {
                    Resolve-TokenForProperty `
                        -MergeCondenserFeedback $MergeCondenserFeedback `
                        -Property $propObject `
                        -Signal $Signal `
                        -ItemSignal $ItemSignal `
                        -Plan $Plan `
                        -HydrationStyle $HydrationStyle `
                        -RegexPattern $RegexPattern `
                        -ReturnRequiredValues:$ReturnRequiredValues | Select-Object -Last 1 | Out-Null
                }
            }
            catch {
                Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Failed during second-pass token resolution for '$Key'. $($_.Exception.Message)"
                return
            }

            try {
                $propertyValue = $propObject.Value

                if ($propertyValue -is [string] -and $null -ne $propertyValue) {
                    $parsed = Invoke-ParseJsonString -_input $propertyValue
                    if ($null -ne $parsed) {
                        $propertyValue = $parsed
                    }
                }
            }
            catch {
                Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Failed while deserializing property '$Key'. $($_.Exception.Message)"
                return
            }

            try {
                Add-PathToDictionary -Dictionary $Parent -Path $Key -Value $propertyValue | Select-Object -Last 1 | Out-Null

                if ($null -ne $ReplacementCount -and -not [object]::Equals($originalPropertyValue, $propertyValue)) {
                    $ReplacementCount.Value++
                }
            }
            catch {
                Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Failed while writing resolved property '$Key'. $($_.Exception.Message)"
                return
            }
        }
        catch {
            Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "_ResolveAndDeserializeProperty failed for '$Key'. $($_.Exception.Message)"
            return
        }
    }

    function _Walk {
        param (
            [Signal]$Signal,
            [object]$Plan,
            [Signal]$ItemSignal,
            [object]$Parent,
            [object]$Key,
            [string]$RegexPattern
        )

        try {
            try {
                $valueSignal = Resolve-PathFromDictionary -Dictionary $Parent -Path $Key | Select-Object -Last 1
                if ($valueSignal.Failure()) {
                    return
                }
                $value = $valueSignal.GetResult()

                if ($null -eq $value) {
                    return
                }

                $valueTypeName = $value.GetType().Name
            }
            catch {
                Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Walk failed while reading type for '$Key'. $($_.Exception.Message)"
                return
            }

            switch ($valueTypeName) {
                'Hashtable' {
                    try {
                        foreach ($subKey in $value.Keys) {
                            try {
                                _Walk -Signal $Signal `
                                    -ItemSignal $ItemSignal `
                                    -Plan $Plan `
                                    -Parent $value `
                                    -Key $subKey `
                                    -RegexPattern $RegexPattern
                            }
                            catch {
                                Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Walk failed for hashtable child '$subKey'. $($_.Exception.Message)"
                            }
                        }
                    }
                    catch {
                        Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Walk failed while enumerating hashtable at '$Key'. $($_.Exception.Message)"
                    }
                }
                'PSCustomObject' {
                    try {
                        foreach ($prop in $value.PSObject.Properties) {
                            try {
                                _Walk -Signal $Signal `
                                    -ItemSignal $ItemSignal `
                                    -Plan $Plan `
                                    -Parent $value `
                                    -Key $prop.Name `
                                    -RegexPattern $RegexPattern
                            }
                            catch {
                                Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Walk failed for object property '$($prop.Name)'. $($_.Exception.Message)"
                            }
                        }
                    }
                    catch {
                        Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Walk failed while enumerating object properties at '$Key'. $($_.Exception.Message)"
                    }
                }
                'Object[]' {
                    try {
                        for ($i = 0; $i -lt $value.Count; $i++) {
                            try {
                                if ($null -eq $value[$i]) {
                                    continue
                                }
                                elseif ($value[$i] -is [hashtable] -or $value[$i] -is [pscustomobject]) {
                                    _Walk -Signal $Signal `
                                        -ItemSignal $ItemSignal `
                                        -Plan $Plan `
                                        -Parent $value `
                                        -Key $i `
                                        -RegexPattern $RegexPattern
                                }
                                elseif ($value[$i] -is [string] -and $value[$i] -match $RegexPattern) {
                                    _ResolveAndDeserializeProperty `
                                        -Signal $Signal `
                                        -ItemSignal $ItemSignal `
                                        -Plan $Plan `
                                        -MergeCondenserFeedback $MergeCondenserFeedback `
                                        -Parent $value `
                                        -Key "$i" `
                                        -HydrationStyle $HydrationStyle `
                                        -ReturnRequiredValues:$ReturnRequiredValues `
                                        -RegexPattern $RegexPattern
                                }
                            }
                            catch {
                                Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Walk failed for array index '$i'. $($_.Exception.Message)"
                            }
                        }
                    }
                    catch {
                        Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Walk failed while enumerating array at '$Key'. $($_.Exception.Message)"
                    }
                }
                'String' {
                    try {
                        if ($value -match $RegexPattern) {
                            _ResolveAndDeserializeProperty `
                                -MergeCondenserFeedback $MergeCondenserFeedback `
                                -Parent $Parent `
                                -Key $Key `
                                -Signal $Signal `
                                -ItemSignal $ItemSignal `
                                -Plan $Plan `
                                -HydrationStyle $HydrationStyle `
                                -ReturnRequiredValues:$ReturnRequiredValues `
                                -RegexPattern $RegexPattern
                        }
                    }
                    catch {
                        Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Walk failed while resolving string token at '$Key'. $($_.Exception.Message)"
                    }
                }
            }
        }
        catch {
            Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "_Walk failed for key '$Key'. $($_.Exception.Message)"
            return
        }
    }

    try {
        if ($CurrentObject -is [hashtable]) {
            try {
                foreach ($key in $CurrentObject.Keys) {
                    try {
                        _Walk -Signal $Signal `
                            -ItemSignal $ItemSignal `
                            -Plan $Plan `
                            -Parent $CurrentObject `
                            -Key $key `
                            -RegexPattern $RegexPattern
                    }
                    catch {
                        Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Invoke-TokenCrawl failed for root hashtable key '$key'. $($_.Exception.Message)"
                    }
                }
            }
            catch {
                Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Invoke-TokenCrawl failed while enumerating root hashtable. $($_.Exception.Message)"
            }
        }
        elseif ($CurrentObject -is [pscustomobject]) {
            try {
                foreach ($prop in $CurrentObject.PSObject.Properties) {
                    try {
                        _Walk -Signal $Signal `
                            -ItemSignal $ItemSignal `
                            -Plan $Plan `
                            -Parent $CurrentObject `
                            -Key $prop.Name `
                            -RegexPattern $RegexPattern
                    }
                    catch {
                        Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Invoke-TokenCrawl failed for root property '$($prop.Name)'. $($_.Exception.Message)"
                    }
                }
            }
            catch {
                Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Invoke-TokenCrawl failed while enumerating root object. $($_.Exception.Message)"
            }
        }
        elseif ($CurrentObject -is [array]) {
            try {
                for ($i = 0; $i -lt $CurrentObject.Count; $i++) {
                    try {
                        if ($null -eq $CurrentObject[$i]) {
                            continue
                        }

                        _Walk -Signal $Signal `
                            -ItemSignal $ItemSignal `
                            -Plan $Plan `
                            -Parent $CurrentObject `
                            -Key $i `
                            -RegexPattern $RegexPattern
                    }
                    catch {
                        Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Invoke-TokenCrawl failed for root array index '$i'. $($_.Exception.Message)"
                    }
                }
            }
            catch {
                Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Invoke-TokenCrawl failed while enumerating root array. $($_.Exception.Message)"
            }
        }

        return $MergeCondenserFeedback
    }
    catch {
        Write-TokenCrawlCritical -Feedback $MergeCondenserFeedback -Message "Invoke-TokenCrawl failed with an unhandled exception. $($_.Exception.Message)"
        return $MergeCondenserFeedback
    }
}
