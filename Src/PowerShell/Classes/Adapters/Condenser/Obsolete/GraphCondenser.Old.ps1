# =============================================================================
# 🧩 GridCondenser (Tag Replacement + Textual Mini-Condenser)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☠️🧁👾️/🤖 • Neural Alchemist ⚗️☣️🐲 • Last Updated: 05/20/2025
# =============================================================================
# This component performs lightweight string-based condensation using tag scanning
# and source overlay. Designed for proposal-to-template synthesis, where symbolic
# tags such as @@TAG or ##TAG are replaced using sovereign memory maps.
#
# Memory-safe, signal-tracked, and designed for ceremonial use in Condenser layers.
# =============================================================================

class GridCondenser {
    [Conductor]$Conductor
    [MappedCondenserAdapter]$MappedCondenserAdapter
    [Signal]$Signal  # Sovereign control signal

    GridCondenser() {
        # Constructor intentionally empty; use Start() method.
    }

    static [GridCondenser] Start([MappedCondenserAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [GridCondenser]::new()
        $instance.MappedCondenserAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("GridCondenser.Control") | Select-Object -Last 1
        return $instance
    }

    [Signal] CondenseMini([object]$Proposal, [object]$CancellationToken, [string]$OverrideTemplatePath = $null) {
        $opSignal = [Signal]::Start("CondenseMini") | Select-Object -Last 1
        $opSignal.Result = [PSCustomObject]@{ Content = "" }

        $variableTags = $this.GetVariableTags($Proposal.Content, $Proposal.ReplacementType)

        foreach ($tag in $variableTags) {
            foreach ($source in $Proposal.SourceRelayList) {
                $relayData = $Proposal.RelayData | Where-Object { $_.Key.RelayFilename -eq $source }
                if ($relayData.Value) {
                    $sourceItem = Resolve-PathFromDictionaryNoSignal -Dictionary $relayData.Value -Path $tag
                    if ($sourceItem) {
                        $Proposal.Content = $this.UpdateStringValues($Proposal.Content, $sourceItem.ToString(), $tag, $Proposal.MappingType, $Proposal.ReplacementType)
                    }
                }
            }
        }

        $opSignal.Result.Content = $Proposal.Content
        return $opSignal
    }

    [string] UpdateStringValues([string]$InputValue, [string]$AugmentedValue, [string]$LookupTag, [string]$MappingType, [string]$ReplacementType) {
        if ($null -eq $InputValue) { return $null }

        switch ($MappingType) {
            'Set' {
                return $AugmentedValue
            }
            default {
                $replacements = $this.GetReplacementStrings($LookupTag, $ReplacementType)
                foreach ($r in $replacements) {
                    $InputValue = $InputValue.Replace($r, $AugmentedValue)
                }
                return $InputValue
            }
        }

        return $null
    }

    [string[]] GetReplacementStrings([string]$LookupTag, [string]$ReplacementType) {
        $list = @()
        switch ($ReplacementType) {
            'XmlTag' { $list += "&lt;$LookupTag /&gt;"; $list += "<$LookupTag />" }
            'AtAttag' { $list += "@@$LookupTag" }
            'HashHashtag' { $list += "##$LookupTag" }
            default { }
        }
        return $list
    }

    [string[]] GetVariableTags([string]$InputValue, [string]$ReplacementType) {
        if ($null -eq $InputValue) { return @() }

        switch ($ReplacementType) {
            'AtAttag' {
                return [regex]::Matches($InputValue, "@@[a-zA-Z0-9-]+") | ForEach-Object { $_.Value.Substring(2) }
            }
            'HashHashtag' {
                return [regex]::Matches($InputValue, "##[a-zA-Z0-9_.-]+") | ForEach-Object { $_.Value.Substring(2) }
            }
            default {
                return @()
            }
        }

        return $null
    }
}
