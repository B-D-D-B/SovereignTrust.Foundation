
function Resolve-PathGraph {
    param (
        [Parameter(Mandatory)][string]$WirePath,
        [Parameter(Mandatory)][string]$StrategyType,
        [Parameter()][object]$Conductor,
        [Parameter()][object]$Environment
    )

    # ░▒▓█ SIGNAL INIT █▓▒░
    $signal = [Signal]::Start("Resolve-PathGraph:$WirePath") | Select-Object -Last 1

    # ░▒▓█ STRATEGY RESOLVER TABLE █▓▒░
    $strategyTable = @{
        "Publisher" = {
            Resolve-PathGraphForPublisher -WirePath $WirePath -Environment $Environment
        }
        "Module" = {
            Resolve-ModulePathSignal -WirePath $WirePath
        }
        "Condenser" = {
            Resolve-PathGraphCondenserAdapter -Conductor $Conductor
        }
    }

    if (-not $strategyTable.ContainsKey($StrategyType)) {
        $signal.LogCritical("Unknown strategy type: $StrategyType")
        return $signal
    }

    # ░▒▓█ RESOLVE USING STRATEGY █▓▒░
    $innerSignal = & $strategyTable[$StrategyType] | Select-Object -Last 1

    if ($signal.MergeSignalAndVerifySuccess($innerSignal)) {
        $graphResult = $innerSignal.GetResult()

        $signal.SetResult(@{
            Strategy = $StrategyType
            WirePath = $WirePath
            Graph    = $graphResult
        })

        $signal.LogInformation("✅ Resolved graph using strategy '$StrategyType'.")
    } else {
        $signal.LogCritical("Failed to resolve graph using strategy '$StrategyType'.")
    }

    return $signal
}


<#
HISTORICAL DESIGN NOTE (2025.5.3)
Earlier path-formula prose described a Graph preloaded with Manifest, Source,
AdapterJacket, and deep hydration. That was design intent; this function body
does not construct or hydrate those fields.

Observed source path: dispatch Publisher, Module, or Condenser; obtain the
selected inner Signal; and, when its merge reports success, set the operation
Signal result to a hashtable with Strategy, WirePath, and Graph. The Module
branch delegates to Resolve-ModulePathSignal, whose source prepares a module
path Signal without hydration or file access. Runtime outcomes remain unverified.

Signature: ∞⟲⟁⚡ (Recursive Builder Flow)
#>
