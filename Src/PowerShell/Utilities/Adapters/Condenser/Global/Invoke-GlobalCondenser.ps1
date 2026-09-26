# =============================================================================
# 🚦 Invoke-ConductionCondenser
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☚️🐝🤖/ • Neural Alchemist ⚗️☣️🐲 • Version: 2025.5.22
# =============================================================================
# Invokes Conduction phase processing using a sovereign Graph structure and
# interprets each Phase block in sequence or via branching (OnSuccess / OnFail).
# Compatible with the SDA GridCondenser pipeline and sovereign runtime standards.
# =============================================================================

function Invoke-GlobalCondenser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [Signal]$Signal,
        [Parameter(Mandatory)] [object]$Plan,
        [Parameter(Mandatory)] [object]$ItemSignal,
        [string]$HydrationStyle = "",
        [string]$RegexPattern = "\[[^\[@]*=[^/]*\/\]"
    )

    if ($HydrationStyle -eq "Deferred") {
        $RegexPattern = "\[[^\[@]*=[^|]*\|\]"
    }

    $opSignal = [Signal]::Start("Invoke-GlobalCondenser", $Signal) | Select-Object -Last 1
    $result = $ItemSignal.GetResult()

    $MergeCondenserFeedback = $opSignal
    $Dictionary = $null
    $DictionaryName = "DefaultGlobalDictionary"
    $ReturnRequiredValues = $true

    Invoke-GlobalTokenCrawl -MergeCondenserFeedback $MergeCondenserFeedback `
        -CurrentObject $result `
        -Signal $Signal `
        -HydrationStyle $HydrationStyle `
        -RegexPattern $RegexPattern `
        -ReturnRequiredValues:$ReturnRequiredValues

    $opSignal.LogInformation("✅ Global Condenser executed.")
    $opSignal.SetResult($false)  # HACK – Needs real change detection
    return $opSignal
}

function Invoke-GlobalTokenCrawl {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [Signal]$Signal,
        [object]$MergeCondenserFeedback,
        [object]$CurrentObject,
        [string]$RegexPattern,
        [string]$HydrationStyle = "",
        [bool]$ReturnRequiredValues = $true
    )

    function _Walk {
        param (
            [object]$Parent,
            [object]$Key,
            [string]$RegexPattern,
            [string]$HydrationStyle
        )

        if ($Key -is [int]) {
            if ($Key -ge 0 -and $Key -lt $Parent.Count) {
                $value = $Parent[$Key]
            } else { return }
        } else {
            $valueSignal = Resolve-PathFromDictionary -Dictionary $Parent -Path $Key | Select-Object -Last 1
            if ($valueSignal.Failure()) { return }
            $value = $valueSignal.GetResult()
        }

        if ($null -eq $value) { return }

        switch ($value.GetType().Name) {
            'Hashtable' {
                foreach ($subKey in $value.Keys) {
                    _Walk -Parent $value -Key $subKey -RegexPattern $RegexPattern -HydrationStyle $HydrationStyle
                }
            }
            'PSCustomObject' {
                foreach ($prop in $value.PSObject.Properties) {
                    _Walk -Parent $value -Key $prop.Name -RegexPattern $RegexPattern -HydrationStyle $HydrationStyle
                }
            }
            'Object[]' {
                for ($i = 0; $i -lt $value.Count; $i++) {
                    if ($value[$i] -is [hashtable] -or $value[$i] -is [pscustomobject]) {
                        _Walk -Parent $value -Key $i -RegexPattern $RegexPattern -HydrationStyle $HydrationStyle
                    } elseif ($value[$i] -is [string] -and $value[$i] -match $RegexPattern) {
                        $propObject = [PSCustomObject]@{ Name = "$i"; Value = $value[$i] }
                        Resolve-TokenForProperty -Signal $Signal `
                            -MergeCondenserFeedback $MergeCondenserFeedback `
                            -Property $propObject `
                            -SplitMatchCharacter '=' `
                            -ReturnRequiredValues:$ReturnRequiredValues `
                            -HydrationStyle $HydrationStyle | Out-Null
                        $value[$i] = $propObject.Value
                    }
                }
            }
            'String' {
                if ($value -match $RegexPattern) {
                    $propObject = [PSCustomObject]@{ Name = $Key; Value = $value }
                    Resolve-TokenForProperty -Signal $Signal `
                        -MergeCondenserFeedback $MergeCondenserFeedback `
                        -Property $propObject `
                        -SplitMatchCharacter '=' `
                        -ReturnRequiredValues:$ReturnRequiredValues `
                        -HydrationStyle $HydrationStyle | Out-Null
                    Add-PathToDictionary -Dictionary $Parent -Path $Key -Value $propObject.Value | Out-Null
                }
            }
        }
    }

    if ($CurrentObject -is [hashtable]) {
        foreach ($key in $CurrentObject.Keys) {
            _Walk -Parent $CurrentObject -Key $key -RegexPattern $RegexPattern -HydrationStyle $HydrationStyle
        }
    } elseif ($CurrentObject -is [pscustomobject]) {
        foreach ($prop in $CurrentObject.PSObject.Properties) {
            _Walk -Parent $CurrentObject -Key $prop.Name -RegexPattern $RegexPattern -HydrationStyle $HydrationStyle
        }
    }
}
