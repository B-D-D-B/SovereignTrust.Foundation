using module SignalGraph

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Src/PowerShell/SovereignTrust.Foundation.psd1') -Force

function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$bootstrap = [Signal]::Start('FamilyRouting.Bootstrap') | Select-Object -Last 1
$bootstrap.SetResult([pscustomobject]@{}) | Out-Null
$created = New-Conductor -HostConductor $null -ConductionSignal $bootstrap | Select-Object -Last 1
Assert (-not $created.Failure() -and $created.HasResult()) 'Family routing conductor failed.'
$conductor = $created.GetResult()
$control = [Signal]::Start('FamilyRouting.Control') | Select-Object -Last 1
$control.SetJacket($conductor.Signal) | Out-Null
$control.SetPointer($conductor.Signal.GetPointer()) | Out-Null
$run = [Signal]::Start('FamilyRouting.Run') | Select-Object -Last 1
$run.SetControl($control) | Out-Null
$run.SetPointer($conductor.Signal.GetPointer()) | Out-Null
$item = [Signal]::Start('FamilyRouting.Item') | Select-Object -Last 1
$item.SetPointer($conductor.Signal.GetPointer()) | Out-Null

$familyActivities = @{ Intelligence='SendMessage'; Satellite='EmitSignal'; Network='SendMessage'; Queue='ReadBatch' }
foreach ($family in @('Intelligence','Satellite','Network','Queue')) {
    $adapter = [pscustomobject]@{ Kind=$family; Slot="Probe$family"; VirtualPath="SovereignTrust.Adapters.$family.Fixture.Probe$family" }
    $adapter | Add-Member -MemberType ScriptMethod -Name Invoke -Value {
        param($slot,$activity,$signal,$plan,$itemSignal)
        $result = [Signal]::Start("FamilyRouting.$slot") | Select-Object -Last 1
        if ($plan.Fail) { $result.LogCritical('Expected provider failure.') | Out-Null }
        else { $result.SetResult([pscustomobject]@{ Kind=$this.Kind; Slot=$slot; Activity=$activity; Plan=$plan; Item=$itemSignal }) | Out-Null }
        return $result
    }
    $registration = Register-AdapterToMappedSlot -ConductorJacketSignal $conductor.Signal -Signal $run -ConductionContext $conductor.Signal -Adapter $adapter | Select-Object -Last 1
    Assert (-not $registration.Failure()) "$family registration failed."
    $plan = [pscustomobject]@{ Adapter="$family.Probe$family"; Activity=$familyActivities[$family]; Fail=$false }
    $invoked = Invoke-MappedAdapter -Adapter $plan.Adapter -Activity $plan.Activity -Signal $run -Plan $plan -ItemSignal $item | Select-Object -Last 1
    Assert (-not $invoked.Failure() -and $invoked.HasResult()) "$family route failed."
    $result = $invoked.GetResult()
    Assert ($result.Kind -ceq $family -and $result.Slot -ceq "Probe$family" -and $result.Activity -ceq $plan.Activity -and [object]::ReferenceEquals($result.Plan,$plan) -and [object]::ReferenceEquals($result.Item,$item)) "$family payload crossed family or changed."
    $plan.Fail = $true
    $failed = Invoke-MappedAdapter -Adapter $plan.Adapter -Activity $plan.Activity -Signal $run -Plan $plan -ItemSignal $item | Select-Object -Last 1
    Assert ($failed.Failure()) "$family provider failure was lost."
}
foreach ($old in @('Network.ProbeIntelligence','Network.ProbeSatellite','Telemetry.ProbeSatellite')) {
    $route = Invoke-MappedAdapter -Adapter $old -Activity 'SendMessage' -Signal $run -Plan ([pscustomobject]@{}) -ItemSignal $item | Select-Object -Last 1
    Assert ($route.Failure()) "Old or cross-family route $old succeeded."
}
$missingTelemetry = Invoke-Telemetry -Signal $run -ItemSignal $item | Select-Object -Last 1
Assert ($missingTelemetry.Failure()) 'Unbound Satellite.Telemetry callback silently succeeded.'
$telemetry = [pscustomobject]@{ Kind='Satellite'; Slot='Telemetry'; VirtualPath='SovereignTrust.Adapters.Satellite.Fixture.Telemetry' }
$telemetry | Add-Member -MemberType ScriptMethod -Name Invoke -Value {
    param($slot,$activity,$signal,$plan,$itemSignal)
    $result = [Signal]::Start('FamilyRouting.Telemetry') | Select-Object -Last 1
    $result.SetResult([pscustomobject]@{ Slot=$slot; Activity=$activity; Item=$itemSignal }) | Out-Null
    return $result
}
$registeredTelemetry = Register-AdapterToMappedSlot -ConductorJacketSignal $conductor.Signal -Signal $run -ConductionContext $conductor.Signal -Adapter $telemetry | Select-Object -Last 1
Assert (-not $registeredTelemetry.Failure()) 'Satellite telemetry registration failed.'
$boundTelemetry = Invoke-Telemetry -Signal $run -ItemSignal $item | Select-Object -Last 1
Assert (-not $boundTelemetry.Failure() -and $boundTelemetry.HasResult()) 'Bound Satellite telemetry callback failed.'
Assert ($boundTelemetry.GetResult().Slot -ceq 'Telemetry' -and $boundTelemetry.GetResult().Activity -ceq 'EmitSignalFull' -and [object]::ReferenceEquals($boundTelemetry.GetResult().Item,$item)) 'Bound telemetry callback changed route or payload.'
Write-Output 'PASS: family registration, selected slot, payload, failure, isolation and bound/unbound telemetry callback.'

$global:FamilyLazyResolutionCount = @{}
& (Get-Module SovereignTrust.Foundation) {
    Set-Item -Path Function:script:Resolve-AdapterFromJacket -Value {
        param([Signal]$Signal, [object]$ConductionContext, [object]$Jacket)
        $metadata = if ($Jacket -is [Signal]) { $Jacket.GetResult() } else { $Jacket }
        $family = [string]$metadata.Kind
        $global:FamilyLazyResolutionCount[$family] = 1 + [int]$global:FamilyLazyResolutionCount[$family]
        $instance = [pscustomobject]@{ Kind=$family; Id=[guid]::NewGuid().ToString() }
        $instance | Add-Member -MemberType ScriptMethod -Name Invoke -Value {
            param($slot,$activity,$signal,$plan,$itemSignal)
            $result = [Signal]::Start("FamilyLazy.$slot") | Select-Object -Last 1
            $result.SetResult([pscustomobject]@{ Kind=$this.Kind; Id=$this.Id; Slot=$slot; Activity=$activity; Signal=$signal; Plan=$plan; Item=$itemSignal }) | Out-Null
            return $result
        }
        $resolved = [Signal]::Start("FamilyLazy.Resolve.$family") | Select-Object -Last 1
        $resolved.SetResult($instance) | Out-Null
        return $resolved
    }
}
foreach ($family in @('Intelligence','Satellite')) {
    $slot = "Lazy$family"
    $jacket = [Signal]::Start("FamilyLazy.Jacket.$family") | Select-Object -Last 1
    $jacket.SetResult([pscustomobject]@{ Kind=$family; Slot=$slot; VirtualPath="SovereignTrust.Adapters.$family.Fixture.$slot" }) | Out-Null
    $registration = Register-AdapterToMappedSlot -ConductorJacketSignal $conductor.Signal -Signal $run -ConductionContext $conductor.Signal -Adapter $jacket -Lazy | Select-Object -Last 1
    Assert (-not $registration.Failure()) "$family lazy registration failed."
    Assert (-not $global:FamilyLazyResolutionCount.ContainsKey($family)) "$family resolved during registration."
    $plan = [pscustomobject]@{ Adapter="$family.$slot"; Activity=$familyActivities[$family] }
    $first = Invoke-MappedAdapter -Adapter $plan.Adapter -Activity $plan.Activity -Signal $run -Plan $plan -ItemSignal $item | Select-Object -Last 1
    Assert (-not $first.Failure() -and $first.HasResult() -and $global:FamilyLazyResolutionCount[$family] -eq 1) "$family did not resolve exactly once on first use."
    $firstResult = $first.GetResult()
    Assert ($firstResult.Kind -ceq $family -and $firstResult.Slot -ceq $slot -and $firstResult.Activity -ceq $plan.Activity -and [object]::ReferenceEquals($firstResult.Signal,$run) -and [object]::ReferenceEquals($firstResult.Plan,$plan) -and [object]::ReferenceEquals($firstResult.Item,$item)) "$family lazy invocation lost five-argument identity."
    $second = Invoke-MappedAdapter -Adapter $plan.Adapter -Activity $plan.Activity -Signal $run -Plan $plan -ItemSignal $item | Select-Object -Last 1
    Assert (-not $second.Failure() -and $global:FamilyLazyResolutionCount[$family] -eq 1 -and $second.GetResult().Id -ceq $firstResult.Id) "$family lazy cached reuse failed."
    $cross = Invoke-MappedAdapter -Adapter "Network.$slot" -Activity 'SendMessage' -Signal $run -Plan $plan -ItemSignal $item | Select-Object -Last 1
    Assert ($cross.Failure()) "$family lazy slot resolved through Network."
}
Write-Output 'PASS: Intelligence and Satellite lazy first use, cached reuse, payload identity and isolation.'
