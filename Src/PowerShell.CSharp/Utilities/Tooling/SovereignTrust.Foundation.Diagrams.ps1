function Emit-SignalTreeLine {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][Signal]$Target,
        [Parameter(Mandatory)][string]$Line,
        [string]$Level = "Information",
        [string]$TraceID,
        [string]$TraceScope,
        [bool]$Minimal = $false
    )

    $emit = [Signal]::Start("Emit:") | Select-Object -Last 1

    # Only prefix if not already present
    $formatted = if ($Minimal) {
        $trimmed = $Line -replace '^.*?\]\s*', ''
        "🛰️  SignalTree: $trimmed"
    } else {
        "📡 SignalTree: [TraceID=$TraceID Scope=$TraceScope] $Line"
    }

    # Downgrade to Verbose if line ends in `$null`
    if ($formatted -like "*= `$null" -and $Level -eq "Information") {
        $Level = "Verbose"
    }

    if ($Minimal) {
        $emit.LogDiagram($formatted)
    } else {
        switch ($Level.ToLower()) {
            "verbose"     { $emit.LogVerbose($formatted) }
            "warning"     { $emit.LogWarning($formatted) }
            "critical"    { $emit.LogCritical($formatted) }
            default       { $emit.LogInformation($formatted) }
        }
    }

    return $emit
}

function Emit-SignalTreeBoundary {
    param (
        [Parameter(Mandatory)][Signal]$Target,
        [Parameter(Mandatory)][string]$Direction,  # Begin or End
        [Parameter()][string]$TraceID,
        [Parameter()][string]$TraceScope
    )

    $line = if ($Direction -eq "Begin") {
        "┌── Begin SignalTree Trace"
    } else {
        "└── End SignalTree Trace"
    }

    return Emit-SignalTreeLine -Target $Target -Line $line -TraceID $TraceID -TraceScope $TraceScope -Minimal $true
}
