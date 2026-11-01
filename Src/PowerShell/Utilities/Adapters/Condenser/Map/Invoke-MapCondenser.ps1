using module SignalGraph

function Invoke-MapCondenser {
    [CmdletBinding()]
    param (
        [Signal]$Signal,
        [object]$ProposalSignal,
        [object]$Context = $null
    )

    $opSignal = [Signal]::Start("Invoke-MapCondenser", $Signal) | Select-Object -Last 1

    if ($ProposalSignal -isnot $Signal.GetType() -or -not $ProposalSignal.HasResult()) {
        $opSignal.LogCritical("Proposal must be a Signal with a Result.")
        return $opSignal
    }

    $modeSignal = Resolve-PathFromDictionary -Dictionary $ProposalSignal -Path "@.CondenserMode" -SignalLevel "Warning" -SignalTags @("Verbose") | Select-Object -Last 1
    if ($modeSignal.HasResult()) {
        $mode = $modeSignal.GetResult()
    }

    if ([string]::IsNullOrWhiteSpace($mode)) {
        $mode = 'Direct'
        $opSignal.LogVerbose("ℹ️ Defaulting CondenserMode to 'Direct'.")
    }

    switch ($mode) {
        'Direct' {
            $directResult = Invoke-DirectMapCondenser -Signal $Signal -Context $Context -ProposalSignal $ProposalSignal | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure($directResult)) {
                $opSignal.LogCritical("DirectMapCondenser failed.")
                return $opSignal
            }
            else {
                $opSignal.SetResult($directResult.GetResult())
            }

            return $opSignal
        }

        'Template' {
            $templateResult = Invoke-TemplateMapCondenser -Signal $opSignal -Proposal $ProposalSignal -Context $Context
            return $templateResult
        }

        default {
            $opSignal.LogCritical("Unknown CondenserMode: $mode")
            return $opSignal
        }
    }
}
