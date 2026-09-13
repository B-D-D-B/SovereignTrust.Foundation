# Reusable environment initialization

`Initialize-STEnvironment` builds a fresh conductor and its environment graph,
without running a conduction plan or entering the SDAFusion service loop.
`Invoke-ST` uses this same function during startup, so `Launch-All.ps1` reaches it
through the existing `Invoke-SDAFusion` / `Invoke-ST` call path.

Pass the complete JSON-compatible environment definition: `Name`, `Config`, and
`Steps`, as currently assembled in `Launch-All.ps1`. The `GetAdapters` step selects
`SDAFusionApp.json` and the machine/role path; the following steps register adapters
and load bootstrap content. The initializer does not hardcode an application,
machine, role, or service plan. `Config.ContentRootPath` is required.

```powershell
Import-Module 'C:/GitHub/SiliconDreamArtists/SovereignTrust.Foundation/Src/PowerShell/SovereignTrust.Foundation.psd1'

$buildSignal = Initialize-STEnvironment -Environment $environmentDefinition
if ($buildSignal.Failure()) { return $buildSignal }
$runtime = $buildSignal.GetResult()
```

The result exposes:

| Property | Purpose |
| --- | --- |
| `Environment` | Private copy of the bootstrap definition |
| `EnvironmentSignal` | Environment jacket and graph populated during bootstrap |
| `Conductor` | Initialized conductor instance |
| `ConductorSignal` | The conductor's own signal |
| `ConductorJacketSignal` | Control context for resolving mapped adapters |
| `ConductionSignal` | Ready execution signal with its control context connected |

Each call copies the definition before hydration and builds new runtime objects.
Existing session loggers are preserved; missing default loggers are initialized.
Treat the definition as data: runtime objects, credentials represented as live
objects, and adapter instances are not supported JSON inputs.

An isolated iteration script can use the same initializer after importing the
module in its own session. Once initialized, it can create its item graph and
invoke the target activity directly:

```powershell
# $iterationPlan is an independent plan; $iteration and $iterationName are inputs.
$itemSignal = Start-SignalWrapper -Name 'IterationItem' -ReversePointer $runtime.ConductionSignal
$itemSignal.SetControl($runtime.ConductorJacketSignal)
$null = $itemSignal.CreateGraph()

$valueSignal = Start-SignalWrapper -Name 'Iteration' -ReversePointer $itemSignal
$valueSignal.SetResult($iteration)
$registration = $itemSignal.Pointer.RegisterSignal($iterationName, $valueSignal)
if ($registration.Failure()) { return $registration }

$iterationPlan.Activity = $iterationPlan.Config.Activity
Invoke-CondenserAdapter -Slot ($iterationPlan.Adapter -split '\.')[1] `
    -Activity $iterationPlan.Activity -Plan $iterationPlan `
    -Signal $runtime.ConductionSignal -ItemSignal $itemSignal |
    Select-Object -Last 1
```

Earlier conduction results are not part of the app configuration. Transfer any
required data separately and register it in the new item graph. Initialize inside
the worker session; do not transfer this live runtime between workers. This API
does not schedule parallel work or change PowerShell class runspace affinity.

Focused tests (using the adjacent SignalGraph checkout and stubbed adapters):

```powershell
pwsh -NoProfile -File ./Tests/Initialize-STEnvironment.Tests.ps1
```
