
function Invoke-TemplateMapCondenser {
    param (
        [Signal]$Signal,
        [object]$Proposal,
        [object]$Context
    )

    $opSignal = [Signal]::Start("Invoke-TemplateMapCondenser", $Signal) | Select-Object -Last 1

    if (-not $Proposal -or -not $Proposal.Content) {
        $opSignal.LogCritical("❌ Invalid or missing Proposal.Content for condensation.")
        return $opSignal
    }

    $variableTags = Get-MapCondenserVariableTags -Content $Proposal.Content -Type $Proposal.ReplacementType

    foreach ($tag in $variableTags) {
        foreach ($source in $Proposal.SourceRelayList) {
            $relayData = $Proposal.RelayData | Where-Object { $_.Key.RelayFilename -eq $source }

            if ($relayData.Value) {
                $resolved = Resolve-PathFromDictionary -Dictionary $relayData.Value -Path $tag
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

    $opSignal.SetResult(@{ Content = $Proposal.Content })
    $opSignal.LogInformation("✅ Template condensation completed.")
    return $opSignal
}