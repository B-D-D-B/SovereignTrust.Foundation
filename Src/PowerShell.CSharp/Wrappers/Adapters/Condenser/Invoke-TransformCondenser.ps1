function Invoke-TransformCondenser {
    [CmdletBinding()]
    param (
        [Signal]$Signal,

        [string]$Activity,

        # Merge Activity
        [object]$Base,
        [object]$Overlay,
        [string]$MergeArrayHandling = "Merge",
        [string]$MergeNullValueHandling = "Keep",
        [int]$Depth = 20
    )

    # ░▒▓█ SIGNAL START █▓▒░
    $opSignal = [Signal]::Start("Invoke-TransformCondenser", $Signal) | Select-Object -Last 1


    # Activity Parameters
    # ░▒▓█ BUILD PLAN █▓▒░
    $plan = [PSCustomObject]@{
        MergeArrayHandling     = $MergeArrayHandling
        MergeNullValueHandling = $MergeNullValueHandling
        Depth                  = $Depth
    }

    # ░▒▓█ BUILD ITEM SIGNAL (Jacket contains Base/Overlay) █▓▒░
    $itemSignalResult = [PSCustomObject]@{
        Base    = $Base
        Overlay = $Overlay
    }
    # Activity Parameters

    $itemSignalResultSignal = [Signal]::Start("Merge.Input", $opSignal) | Select-Object -Last 1
    $itemSignalResultSignal.SetResult($itemSignalResult)

    $itemSignal = [Signal]::Start("Merge.Item", $opSignal) | Select-Object -Last 1
    $null = $itemSignal.SetJacket($itemSignalResultSignal)

    # ░▒▓█ INVOKE VIA ADAPTER (NOT DIRECT) █▓▒░
    $invokeSignal = Invoke-CondenserAdapter `
        -Slot "Transform" `
        -Activity "Merge" `
        -Signal $Signal `
        -Plan $plan `
        -ItemSignal $itemSignal `
    | Select-Object -Last 1

    if ($opSignal.MergeSignalAndVerifyFailure(@($invokeSignal))) {
        $opSignal.LogCritical("Merge via Invoke-CondenserAdapter failed.")
        return $opSignal
    }

    $opSignal.SetResult($invokeSignal.GetResult())
    return $opSignal
}
