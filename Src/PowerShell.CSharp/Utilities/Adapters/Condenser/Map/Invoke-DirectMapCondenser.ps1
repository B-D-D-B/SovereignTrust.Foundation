using module SignalGraph

function Invoke-DirectMapCondenser {
    param (
        [Signal]$Signal,
        [Signal]$ProposalSignal,
        [object]$Context = $null
    )

    $opSignal = [Signal]::Start("Invoke-DirectMapCondenser", $Signal) | Select-Object -Last 1

    $Data = $Signal.GetResult()
    $Proposal = $ProposalSignal.GetResult() 
    $contentSignal = Resolve-PathFromDictionary -Dictionary $ProposalSignal -Path "@.Content" | Select-Object -Last 1
    if ($opSignal.MergeSignalAndVerifyFailure($contentSignal)) {
        $opSignal.LogCritical("❌ Invalid or missing Proposal.Result.Content for condensation.")
        return $opSignal
    }

    $replacementType = "AtAt"
    $replacementTypeSignal = Resolve-PathFromDictionary -Dictionary $ProposalSignal -Path "@.ReplacementType" -SignalLevel "Warning" -SignalTags @("Verbose") | Select-Object -Last 1
    if ($replacementTypeSignal.HasResult()) {
        $replacementType = $replacementTypeSignal.GetResult()
    }

    $content = $contentSignal.GetResult()

    $variableTags = Get-MapCondenserVariableTags -Content $content -Type $replacementType

    foreach ($tag in $variableTags) {
        $token = $tag.TrimStart("@@").TrimStart("##").TrimStart("[").TrimEnd("/]")

        
        
        
        $valueSignal = Resolve-PathFromDictionary -Dictionary $Data -Path $token -SignalLevel "Warning" -SignalTags @("Verbose") | Select-Object -Last 1 
        $value = $null
        if ($valueSignal.HasResult()) {
            $value = $valueSignal.GetResult()
        }
        if ($valueSignal.HasResult()) {

            if ($value -is [array])
            {
                $value = ConvertTo-Json -InputObject @($value) -Depth 15
            }
            elseif ($value -isnot [string])
            {
                $value = ConvertTo-Json -InputObject $value -Depth 15
            }


            $replacementValue = [string]$value
            $literalReplacement = [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $replacementValue }
            $content = [regex]::Replace([string]$content, [regex]::Escape([string]$tag), $literalReplacement)
        }
        if ($false) {
            foreach ($source in $Proposal.SourceRelayList) {
                $relayData = $Proposal.RelayData | Where-Object { $_.Key.RelayFilename -eq $source }

                if ($relayData.Value) {
                    $resolved = Resolve-PathFromDictionaryNoSignal -Dictionary $relayData.Value -Path $tag
                    $opSignal.MergeSignal($resolved)

                    if ($resolved.Success()) {
                        $Proposal.Content = Replace-MapCondenserTags `
                            -Input $Proposal.Content `
                            -Value $resolved.GetResult() `
                            -Tag $tag `
                            -MappingType $Proposal.MappingType `
                            -ReplacementType $Proposal.ReplacementType
                    }
                }
            }
        }
    }

    $opSignal.SetResult($content)
    $opSignal.LogInformation("✅ Direct condensation completed.")
    return $opSignal
}
