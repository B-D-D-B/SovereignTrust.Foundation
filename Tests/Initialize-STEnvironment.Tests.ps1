using module ../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

# Run in a fresh pwsh process. Adapter execution is stubbed; no services are started.
$ErrorActionPreference = 'Stop'
$foundationRoot = Join-Path $PSScriptRoot '../Src/PowerShell'
. "$foundationRoot/Classes/Adapters/Telemetry/ConsoleLogger.ps1"
. "$foundationRoot/Classes/Adapters/Telemetry/SignalTelemeter.ps1"
. "$foundationRoot/Utilities/Conduction/Resolve-Conduit.ps1"
. "$foundationRoot/Utilities/Conduction/Initialize-STEnvironment.ps1"
. "$foundationRoot/Utilities/Invoke-ST.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$script:failureStage = ''
$script:bootstrapCount = 0
$script:telemetryCount = 0

function Resolve-Conductor {
    param([Signal]$Signal)
    $script:bootstrapCount++
    if ($script:failureStage -eq 'Throw') { throw 'Bootstrap exception' }
    $result = [Signal]::Start('StubConductor')
    $result.SetResult([pscustomobject]@{ Signal = [Signal]::Start('Conductor') })
    return $result
}

function Invoke-CondenserAdapter {
    [CmdletBinding()]
    param($Slot, $Activity, $Signal, $Plan, $ItemSignal)
    $result = [Signal]::Start("Stub:$Slot")
    if ($Slot -eq $script:failureStage) {
        $null = $result.LogCritical("$Slot bootstrap failed")
        return $result
    }
    if ($Slot -eq 'Memory') {
        $Plan.Config.Marker = 'Hydrated'
        $environmentGraph = ([Graph]::Start('EnvironmentGraph', $null, $false) | Select-Object -Last 1).GetResult()
        $null = $ItemSignal.SetPointer($environmentGraph)
        if ($script:failureStage -eq 'Transform') {
            $result.SetResult([pscustomobject]@{ Name = 'SourceEnvironment' })
        }
    }
    return $result
}

function Invoke-Telemetry {
    param($Signal, $ItemSignal)
    $script:telemetryCount++
}

$definition = [pscustomobject]@{
    Name = 'test'
    Config = [pscustomobject]@{
        ContentRootPath = 'TestContent'
        Marker = 'Original'
        Process = [pscustomobject]@{ Id = 'process'; ProcessorId = 'processor' }
    }
    Steps = @([pscustomobject]@{
        Name = 'GetAdapters'
        Resource = 'SDAFusionApp.Json'
        Path = 'Agents.test.Roles.test'
    })
}

# An unrelated caller variable must never supply the bootstrap configuration.
$Environment = [pscustomobject]@{ Config = @{ ContentRootPath = 'WrongContent' } }
$output = @(Initialize-STEnvironment -Environment $definition)
Assert-True ($output.Count -eq 1) 'Initializer must emit only its result Signal.'
$built = $output[0]
Assert-True (-not $built.Failure() -and $built.HasResult()) 'Expected a successful runtime.'
$runtime = $built.GetResult()
Assert-True ($runtime.ConductorSignal.GetResult().Config.ContentRootPath -eq 'TestContent') 'Bootstrap used ambient configuration.'
Assert-True ($runtime.Environment.Config.Marker -eq 'Hydrated') 'Bootstrap did not execute environment steps.'
Assert-True ($definition.Config.Marker -eq 'Original') 'Bootstrap mutated the caller definition.'
Assert-True ([object]::ReferenceEquals($runtime.ConductionSignal.GetControl(), $runtime.ConductorJacketSignal)) 'Conduction control is disconnected.'
Assert-True ([object]::ReferenceEquals($runtime.ConductorJacketSignal.GetJacket(), $runtime.ConductorSignal)) 'Conductor jacket is disconnected.'
Assert-True ([object]::ReferenceEquals($runtime.ConductorJacketSignal.GetPointer(), $runtime.EnvironmentSignal.GetPointer())) 'Bootstrap graph was not transferred.'
Assert-True ([object]::ReferenceEquals($runtime.ConductionSignal.GetPointer(), $runtime.EnvironmentSignal.GetPointer())) 'Conduction pointer is disconnected.'
Assert-True ($runtime.ConductionSignal.GetPointer().Grid.Contains('EnvironmentDetails')) 'EnvironmentDetails was not registered in the runtime Graph.'
Assert-True ([object]::ReferenceEquals($runtime.ConductionSignal.GetPointer().Grid['EnvironmentDetails'].GetResult(), $runtime.Environment)) 'EnvironmentDetails does not contain the runtime definition.'
Assert-True (-not [object]::ReferenceEquals($runtime.ConductionSignal.GetPointer().Grid['EnvironmentDetails'].GetResult(), $definition)) 'EnvironmentDetails reused the caller definition.'
Assert-True ($script:telemetryCount -eq 0) 'Initialization must not execute the processor lifecycle.'

$second = (Initialize-STEnvironment -Environment $definition).GetResult()
Assert-True (-not [object]::ReferenceEquals($runtime.Conductor, $second.Conductor)) 'Conductor was reused.'
$runtime.Environment.Steps[0].Resource = 'Changed.Json'
Assert-True ($second.Environment.Steps[0].Resource -eq 'SDAFusionApp.Json') 'Runtime definitions share nested data.'
Assert-True (-not [object]::ReferenceEquals($runtime.EnvironmentSignal.GetPointer(), $second.EnvironmentSignal.GetPointer())) 'Runtime graphs were reused.'

foreach ($stage in @('Fab', 'Memory', 'Transform', 'Throw')) {
    $script:failureStage = $stage
    $failed = Initialize-STEnvironment -Environment $definition
    Assert-True ($failed.Failure() -and -not $failed.HasResult()) "Failure at $stage was reported as a ready runtime."
}
$script:failureStage = ''

$beforeInvalid = $script:bootstrapCount
$invalid = Initialize-STEnvironment -Environment ([pscustomobject]@{ Config = @{ ContentRootPath = '' } })
Assert-True ($invalid.Failure() -and -not $invalid.HasResult()) 'Missing content root was accepted.'
Assert-True ($script:bootstrapCount -eq $beforeInvalid) 'Invalid configuration started adapter initialization.'

$beforeStartup = $script:bootstrapCount
$startup = Invoke-ST -Environment $definition | Select-Object -Last 1
Assert-True (-not $startup.Failure()) 'Invoke-ST failed after extraction.'
Assert-True ($script:bootstrapCount -eq $beforeStartup + 1) 'Startup must bootstrap exactly once.'
Assert-True ($null -ne $startup.GetControl().GetPointer()) 'Startup lost its environment graph.'
Assert-True ($script:telemetryCount -eq 1) 'Startup did not retain its processor telemetry.'

Write-Output 'PASS: initialization, context wiring, independent runtimes, failure propagation, and startup integration.'
