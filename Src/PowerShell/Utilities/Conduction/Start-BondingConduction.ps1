
<#
.SYNOPSIS
Initializes a Bonding Conduction with full sovereign memory handling.

.DESCRIPTION
Reads the input Signal result and, when non-null, attaches it as the Jacket
of a new conduction Signal. Creates a Graph and uses its result as that nested
Signal's Pointer. Returns the operation Signal with the conduction Signal in
its Result; this function does not execute a conduction phase.

.OUTPUTS
Signal – The operation Signal with the nested conduction Signal in its Result.
The nested Signal carries the input result as Jacket and the Graph as Pointer.
For a null input result, returns the output of LogCritical instead.
#>
function Start-BondingConduction {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Signal]$Signal
    )

    # ░▒▓█ START WRAPPER SIGNAL █▓▒░
    $opSignal = [Signal]::Start("Start-BondingConduction", $Signal) | Select-Object -Last 1

    # ░▒▓█ EXTRACT GSG ENVIRONMENT █▓▒░
    $gsg = $Signal.GetResult()
    if ($null -eq $gsg) {
        return $opSignal.LogCritical("❌ No environment result found on input signal.")
    }

    # ░▒▓█ CREATE NEW WORKING GRAPH █▓▒░
    $graphSignal = [Graph]::Start("Graph:BondingConduction", $opSignal, $true) | Select-Object -Last 1
    $graph = $graphSignal.GetResult()
    $opSignal.MergeSignal($graphSignal) | Out-Null

    # ░▒▓█ CREATE CONDUCTION SIGNAL █▓▒░
    $conductionSignal = [Signal]::Start("ConductionSignal:Bonding", $opSignal) | Select-Object -Last 1
    $conductionSignal.SetJacket($gsg) | Out-Null
    $conductionSignal.SetPointer($graph) | Out-Null
    $conductionSignal.LogInformation("🧪 ConductionSignal initialized with sovereign Jacket and Pointer.")

    # ░▒▓█ RETURN WRAPPED SIGNAL █▓▒░
    $opSignal.SetResult($conductionSignal)
    $opSignal.LogInformation("✅ Bonding Conduction successfully initialized.")
    return $opSignal
}
