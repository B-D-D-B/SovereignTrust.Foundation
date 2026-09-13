function Initialize-STEnvironment {
    <#
    .SYNOPSIS
    Builds a fresh runtime without starting a conduction plan or service loop.
    .DESCRIPTION
    Accepts the JSON-compatible environment definition used by Invoke-ST. Its
    Config and Steps select the app definition, adapters, and bootstrap content.
    The returned Signal contains the environment, conductor, and execution signals.
    Import SovereignTrust.Foundation in each session before calling this function.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Environment,

        [Signal]$ParentSignal
    )

    $opSignal = [Signal]::Start("Initialize-STEnvironment", $ParentSignal) | Select-Object -Last 1

    try {
        # Bootstrap may hydrate or modify its plan; never share that plan across runtimes.
        $environmentDefinition = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Environment -Depth 100 -ErrorAction Stop) -Depth 100 -ErrorAction Stop

        if ($null -eq $Global:ConsoleLoggerInstance) {
            $Global:ConsoleLoggerInstance = [ConsoleLogger]::new()
        }
        if ($null -eq $Global:SignalTelemeter) {
            $Global:SignalTelemeter = [SignalTelemeter]::new()
        }

        $environmentSignal = [Signal]::Start("Environment", $opSignal) | Select-Object -Last 1
        $null = $environmentSignal.SetJacketResult($environmentDefinition)

        $conduitSignal = Resolve-Conduit -EnvironmentSignal $environmentSignal | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure(@($conduitSignal))) {
            return $opSignal
        }
        if ($null -eq $conduitSignal -or -not $conduitSignal.HasResult()) {
            $null = $opSignal.LogCritical("Environment initialization did not return a conductor.")
            return $opSignal
        }

        $conductor = $conduitSignal.GetResult()
        $conductorSignal = $conductor.Signal
        if ($null -eq $conductorSignal) {
            $null = $opSignal.LogCritical("Environment initialization returned a conductor without a signal.")
            return $opSignal
        }

        $conductorJacketSignal = [Signal]::Start("Conductor", $environmentSignal) | Select-Object -Last 1
        $null = $conductorJacketSignal.SetJacket($conductorSignal)
        $null = $conductorJacketSignal.SetPointer($environmentSignal.GetPointer())

        $runtimeGraph = $conductorJacketSignal.GetPointer()
        if ($runtimeGraph -isnot [Graph]) {
            $null = $opSignal.LogCritical("Environment initialization did not return a runtime Graph pointer.")
            return $opSignal
        }

        $conductionSignal = [Signal]::Start("Conduction", $opSignal) | Select-Object -Last 1
        $conductionSignal.SetControl($conductorJacketSignal)
        $null = $conductionSignal.SetPointer($runtimeGraph)

        $environmentDetailsSignal = $runtimeGraph.RegisterResultAsSignal("EnvironmentDetails", $environmentDefinition) | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure(@($environmentDetailsSignal))) {
            return $opSignal
        }

        $opSignal.SetResult([PSCustomObject]@{
            Environment            = $environmentDefinition
            EnvironmentSignal      = $environmentSignal
            Conductor              = $conductor
            ConductorSignal        = $conductorSignal
            ConductorJacketSignal  = $conductorJacketSignal
            ConductionSignal       = $conductionSignal
        })
    }
    catch {
        $null = $opSignal.LogCritical("Failed to initialize environment: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}
