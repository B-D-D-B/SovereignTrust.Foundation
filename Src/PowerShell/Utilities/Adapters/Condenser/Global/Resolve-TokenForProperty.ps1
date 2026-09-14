<#
─────────────────────────────────────────────────────────────
📌 GLOBAL TOKEN REGEX FORMATS – Reference for $Pattern input
─────────────────────────────────────────────────────────────

[1] Square Bracket Format (Default Style)
Pattern: "\[[^\[@]*=[^\/]*\/\]"
Matches: [key=value/]
Use: Global substitution with key/value embedded in markup.

[2] Curly Bracket Format
Pattern: "\{([a-zA-Z0-9_-]+)\}"
Matches: {key}
Use: Simple key replacement, no template formatting.

[3] Token Prefix Format
Pattern: "@@KEY:([a-zA-Z0-9_.-]+)"
Matches: @@KEY:some.path.value
Use: Recognizes token paths for late-bound replacements.

[4] Named Template Format
Pattern: "\[\[(\w+):([^\]]+)\]\]"
Matches: [[TKN:some.path.here]]
Use: Useful for multi-type prefix tagging.

[5] Custom XPath Style Format
Pattern: "\[([a-zA-Z0-9_]+)=""([^""]+)""\/\]"
Matches: [environmentName="prod"/]
Use: Used for XPath-like dynamic lookups.

# TODO: Review: Remove Deferred Hydration, using Mappings removes that neccesity?
─────────────────────────────────────────────────────────────
#>

function Resolve-TokenForProperty {
    [CmdletBinding()]
    param (
        [Signal]$Signal,
        [object]$Plan,
        [Signal]$ItemSignal,

        [object]$MergeCondenserFeedback,

        [object]$Property,  # A custom object or hashtable with .Name and .Value

        [bool]$ReturnRequiredValues = $true,

        [string]$RegexPattern = "(?s)\[[^\[@]*=[^\/]*\/\]",

        [string]$HydrationStyle = "",
        [char]$SplitMatchCharacter
    )

    $opSignal = [Signal]::Start("Resolve-TokenForProperty:$($Property.Name)", $null) | Select-Object -Last 1

    if ($HydrationStyle -eq "Deferred") {
        $RegexPattern = "(?s)\[[^\[\]\|]*\|\]"

        # Version to get items when they have [] inside the text.
        #$RegexPattern = "\[(.*?)\|\]"
    }

    try {
        $propertyValue = $Property.Value.ToString()
        $pathSegments = $Property.Name -split '\.'

        $matches = [regex]::Matches($propertyValue, $RegexPattern)

        if ($matches.Count -eq 0) {
            if ($HydrationStyle -eq "Deferred") {
                # Version to get items when they have [] inside the text.
                $RegexPattern = "(?s)\[(.*?)\|\]"

                $matches = [regex]::Matches($propertyValue, $RegexPattern)
            }
        }

        #        if ($matches.Count -gt 100) {
        #
        #            $matches = $matches |
        #            ForEach-Object { $_.Value } |
        #            Select-Object -Unique
        #        }
                
        foreach ($match in $matches) {
            $matchText = $match.Value.Trim()
            $equalsIndex = $matchText.Length - 2

            if ($SplitMatchCharacter) {
                $equalsIndex = $matchText.IndexOf($SplitMatchCharacter)
            }

            if ($equalsIndex -le 1) { continue }

            $key = $matchText.Substring(1, $equalsIndex - 1)

            if ($SplitMatchCharacter) {
                $replacementTemplate = $matchText.Substring($equalsIndex + 1, $matchText.Length - ($equalsIndex + 3))
                $lookupSignal = Scan-DictionaryForValue -Dictionary $Dictionary -PathSegments $pathSegments -Key $key | Select-Object -Last 1
            }
            else {
                $adapterSignal = Resolve-PathFromDictionary -Dictionary ($Signal.GetControl() ?? $Signal) -Path "%.*.#.Adapters.*.#.MappedToken.@" -SignalLevel "Information" | Select-Object -Last 1
                
                $adapter = $adapterSignal.GetResult()

                if ($HydrationStyle -eq "Deferred") {
                    $RegexPattern = "\[[^\[\]\|]*\|\]"
                }

                # Account for line breaks
                if (-not ($RegexPattern -match '^\(\?s\)')) {
                    $RegexPattern = "(?s)$RegexPattern"
                }

                if ($key -like "*ECode*" ) {
                    $a = ""
                }
                <#

                $TokenPlan = (Resolve-ClonePlan -Plan $Plan | Select-Object -Last 1).GetResult()
                $null = Add-PathToDictionary -Dictionary $TokenPlan -Path "Path" -Value $Key
#>

                $TokenPlan = [PSCustomObject]@{
                    Path = $key
                }

                $configSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Config" -SignalLevel "Information" | Select-Object -Last 1
                if ($configSignal.HasResult()) {
                    $null = Add-PathToDictionary -Dictionary $TokenPlan -Path "Config" -Value $configSignal.GetResult()
                }

                #$resultSignal = $adapter.Invoke($key);
                $resultSignal = $adapter.Invoke($key, "Get", $Signal, $TokenPlan, $ItemSignal);
                $opSignal.MergeSignal($resultSignal)
                $lookupSignal = [Signal]::Start("Resolve-TokenForProperty:$($Property.Name)", $null) | Select-Object -Last 1
                
                if ($resultSignal.HasResult()) {
                    $lookupSignal.SetResult($resultSignal.GetResult())
                }
            }

            $opSignal.MergeSignal($lookupSignal)

            if ($lookupSignal.Success() -and $lookupSignal.HasResult()) {

                $replacement = $lookupSignal.GetResult()

                # When a replacement value is a json object, etc, we can't do a replacement and must assume the object is ready to be returned.
                #                if (($replacement -is [PSCustomObject])) {
                #                    $propertyValue = $replacement
                #                }
                #     elseif ($replacement -is [bool]) {
                #         $propertyValue = $replacement
                #     }
                if (($replacement -is [array] -and (-not ($replacement -is [string]))) -and (-not $replacement -is [string[]])) {
                    $propertyValue = $replacement
                }
                else {
                    if ($SplitMatchCharacter) {
                        $replacement = $replacementTemplate -f $key, $lookupSignal.Result
                    }

                    # Escape the whole key again for regex use
                    $escapedKey = [regex]::Escape($key)  # results in "Formatter\\.FilePath"


                    $RegexPattern = "\[$escapedKey.*?\/\]"
                    if ($HydrationStyle -eq "Deferred") {
                        #\[[^\[\]\|]*\|\]
                        $RegexPattern = "\[$escapedKey.*?\|\]"
                    }

                    $innerRegex = [regex]::new($RegexPattern)
                    
                    $oldValue = $propertyValue

                    try {
                        # Test the $propertyValue to see if the current value is being set into a string, if it's going into a blank entry, simply replace instead of doing the regex replacement.
                        $propertyValueTest = $innerRegex.Replace($propertyValue, "")
                        if ($propertyValueTest -eq "") {
                            $propertyValue = $replacement
                        }
                        else {
                            # Massage $replacement into a string if it's being integrated into an existing value.
                            if (($replacement -is [PSCustomObject])) {
                                $replacement = $replacement | ConvertTo-Json -Depth 100 -Compress
                            }

                            elseif (($replacement -is [ordered])) {
                                $replacement = $replacement | ConvertTo-Json -Depth 100 -Compress
                            }

                            elseif ($replacement -is [string[]]) {
                                $replacement = (@($replacement) | ForEach-Object { "`"$_`"" }) -join ", "
                            }

                            # Handles an array.
                            elseif ($replacement -is [object[]]) {
                                # -and
                                #        $replacement.Count -gt 0) {

                                if ($replacement.Count -eq 0) {
                                    $replacement = "[]"
                                }
                                else {
                                    # We have an array of arrays
                                    $replacement = $replacement | ConvertTo-Json -Depth 100 -Compress
                                }
                            }

                            # Handles an array of arrays, like the ELineage.
                            elseif ($replacement -is [object[]] -and
                                $replacement.Count -gt 0 -and
                                ($replacement | ForEach-Object { $_ -is [object[]] })) {

                                # We have an array of arrays
                                $replacement = $replacement | ConvertTo-Json -Depth 100 -Compress
                            }
                            <#
                            # Handles an array of arrays, like the ELineage.
                            elseif ($replacement -is [object[]] -and
                                    $replacement.Count -gt 0) {

                                # We have an array of arrays
                                $replacement = $replacement | ConvertTo-Json -Depth 100 -Compress
                            }
#>
                            elseif ($replacement -is [datetime]) {
                                $replacement = $replacement.ToUniversalTime().ToString("o")
                            }

                            elseif ($replacement -is [bool]) {
                                $replacement = $replacement.ToString()
                            }

                            $propertyValue = $innerRegex.Replace($propertyValue, $replacement)
                        }
                    }
                    catch {
                        $a = $_
                    }

                    if ($propertyValue -ne $oldValue) {
                        $opSignal.LogInformation("🔄 Replaced '$key' with '$replacement' in property '$($Property.Name)'")
                    }
                    else {
                        #  $propertyValue = $propertyValue -replace $match.Value, $replacement
                        $opSignal.LogWarning("No replacement made for '$key' in property '$($Property.Name)' — token may be malformed or missing. ($propertyValue)")
                    }
                }

            }
        }

        $opSignal.MergeSignal((Add-PathToDictionary -Dictionary $Property -Path "Value" -Value $propertyValue | Select-Object -Last 1))
    }
    catch {
        $opSignal.LogCritical("Exception in global token resolution: $($_.Exception.Message)", $null, $_)
        # $null = $MergeCondenserFeedback.MissingWireGlobalFeedback.Invoke("", "", @())
    }

    return $opSignal
}

function Scan-DictionaryForValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [hashtable]$Dictionary,

        [Parameter(Mandatory)]
        [string[]]$PathSegments,

        [Parameter(Mandatory)]
        [string]$Key
    )

    $signal = [Signal]::Start("Scan-DictionaryForValue:$Key", $null) | Select-Object -Last 1

    try {
        $currentDict = $Dictionary
        foreach ($segment in $PathSegments) {
            if ($currentDict.ContainsKey($segment)) {
                $currentDict = $currentDict[$segment]
            }
            else {
                break
            }
        }

        if ($null -ne $currentDict -and $currentDict.ContainsKey($Key)) {
            $signal.SetResult($currentDict[$Key])
        }
        else {
            $signal.SetResult("")
        }
    }
    catch {
        $signal.LogCritical("Failed to extract global '$Key' at path [$($PathSegments -join '.')]: $($_.Exception.Message)")
    }

    return $signal
}
