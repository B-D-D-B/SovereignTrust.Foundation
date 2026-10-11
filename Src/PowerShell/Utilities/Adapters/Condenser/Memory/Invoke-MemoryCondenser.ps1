# =============================================================================
# 🧠 Invoke-MemoryCondenser
#  Delegated logic for Hot Path, Hydration, and Memory Resolution
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom 🤖/☠️🏋️😾️ • Neural Alchemist ⚗️☣️🐲 • Version: 2025.5.4.8
# =============================================================================

function Invoke-MemoryCondenser {
    param (
        [Parameter(Mandatory)][string]$Action,  # "Read", "Write", "Remove", "Move"
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][object]$Value,
        [Parameter()][Signal]$HostSignal,
        [Parameter()][object]$TargetMemory,
        [Parameter()][hashtable]$HydrationPlan,
        [string]$DestinationPath  # Required only for Move
    )

    $opSignal = [Signal]::Start("Invoke-MemoryCondenser:$Action", $HostSignal) | Select-Object -Last 1

    # ░▒▓█ OPTIONAL HYDRATION █▓▒░
    if (-not $HydrationPlan.Skip) {
        $hydrationCheck = Invoke-PathHydration -Path $Path -HostSignal $opSignal -SignalFirst:$true | Select-Object -Last 1
        if ($hydrationCheck.Failure()) { return $opSignal.LogCritical("❌ Path hydration failed.") }
        $Path = $hydrationCheck.GetResult()

        if ($Action -eq "Move" -and $DestinationPath) {
            $destHydration = Invoke-PathHydration -Path $DestinationPath -HostSignal $opSignal -SignalFirst:$true | Select-Object -Last 1
            if ($destHydration.Failure()) { return $opSignal.LogCritical("❌ Destination path hydration failed.") }
            $DestinationPath = $destHydration.GetResult()
        }
    }

    # ░▒▓█ ACTION DELEGATION █▓▒░
    switch ($Action) {
        "Read"   { return Resolve-PathFromDictionary -Dictionary $TargetMemory -Path $Path -SkipPathHydration:$true }
        "Write"  { return Add-PathToDictionary -Dictionary $TargetMemory -Path $Path -Value $Value -SkipPathHydration:$true }
        "Remove" { return Remove-PathFromDictionary -Dictionary $TargetMemory -Path $Path -SkipPathHydration:$true }
        "Move"   {
            if (-not $DestinationPath) {
                return $opSignal.LogCritical("❌ 'Move' action requires -DestinationPath.")
            }
            return Move-PathInDictionary -Dictionary $TargetMemory -SourcePath $Path -DestinationPath $DestinationPath -SkipPathHydration:$true
        }
        default  { return $opSignal.LogCritical("❌ Unknown action '$Action'.") }
    }
}
