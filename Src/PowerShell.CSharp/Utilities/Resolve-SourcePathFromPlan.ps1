function Resolve-SourcePathFromPlan {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $plan
    )

    $opSignal = [Signal]::Start("Resolve-SourcePathFromPlan") | Select-Object -Last 1

    try {
        # Pull plan fields
        $result    = $plan
        $sourcesKey = $result.SourcesWirePath
        $idPath     = $result.SourcesIdentifierWirePath

        # Normalize template (default to '{0}')
        $template  = $result.SourcesWirePathTemplate
        $template  = if ([string]::IsNullOrWhiteSpace($template)) { '{0}' } else { $template }
        $isDefault = ($template -eq '{0}')

        # Enforce token
        if ($template -notmatch '\{0\}') {
            $opSignal.LogCritical("❌ SourcesWirePathTemplate must contain '{0}'. Template: '$template'")
            return $opSignal
        }

        # Build path from template
        $path = [string]::Format($template, $sourcesKey)

        # Set structured result
        $opSignal.SetResult($path)

        return $opSignal

    } catch {
        $opSignal.LogException($_, "❌ Failed in Resolve-SourcePath.")
        return $opSignal
    }
}
