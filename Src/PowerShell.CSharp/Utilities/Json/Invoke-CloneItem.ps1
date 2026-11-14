function Invoke-CloneItem {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )

    # ░▒▓█ SIGNAL START █▓▒░
    $opSignal = [Signal]::Start("Invoke-CloneItem") | Select-Object -Last 1

    try {
        # ░▒▓█ VALIDATE INPUT █▓▒░
        if ($null -eq $InputObject) {
            $opSignal.LogCritical("InputObject is null. Cannot proceed with cloning.")
            return $opSignal
        }

        # ░▒▓█ CLONE THE OBJECT █▓▒░
        $json = $InputObject | ConvertTo-Json -Depth 100
        $clone = $json | ConvertFrom-Json

        # ░▒▓█ STORE RESULT █▓▒░
        $opSignal.SetResult($clone)
        $opSignal.LogInformation("✅ Object cloned successfully.")
        return $opSignal
    }
    catch {
        $opSignal.LogCritical("Exception during cloning: $($_.Exception.Message)", $null, $_)
        return $opSignal
    }
}
