using module ../../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

function Initialize-STEnvironment {
    param([object]$Environment)

    $signal = [Signal]::Start('TestInitialize') | Select-Object -Last 1
    if ([bool]$Environment.FailInitialization) {
        $null = $signal.LogCritical('Requested test initialization failure.')
        return $signal
    }

    $runtimeConductionSignal = [Signal]::Start('TestConduction') | Select-Object -Last 1
    $runtimeGraph = ([Graph]::Start('TestRuntimeGraph', $runtimeConductionSignal, $false) | Select-Object -Last 1).GetResult()
    $null = $runtimeConductionSignal.SetPointer($runtimeGraph)

    $signal.SetResult([PSCustomObject]@{
        Id               = [guid]::NewGuid().ToString()
        Environment      = $Environment
        ConductionSignal = $runtimeConductionSignal
    })
    return $signal
}

function Test-STPoolWorker {
    param(
        [object]$Runtime,
        [object]$WorkItem,
        [object]$Context
    )

    $forkSignal = New-SignalPointerFork `
        -SourceSignal $Context.SourceSignal `
        -Name "WorkerFork:$($WorkItem.Index)" `
        -TargetGraph $Runtime.ConductionSignal.Pointer `
        -CollisionAction PreserveTarget `
    | Select-Object -Last 1

    if ($forkSignal.Failure() -or -not $forkSignal.HasResult()) {
        return $forkSignal
    }

    $forkedSignal = $forkSignal.GetResult()
    $sourceMember = $Context.SourceSignal.Pointer.Grid['State']
    $memberWasReused = [object]::ReferenceEquals($sourceMember, $forkedSignal.Pointer.Grid['State'])
    $replacement = [Signal]::Start("Replacement:$($WorkItem.Index)") | Select-Object -Last 1
    $null = $forkedSignal.Pointer.RegisterSignal('State', $replacement)
    $sourceWasUnaffected = [object]::ReferenceEquals($sourceMember, $Context.SourceSignal.Pointer.Grid['State'])

    Start-Sleep -Milliseconds 50
    $signal = [Signal]::Start("TestWorker:$($WorkItem.Index)") | Select-Object -Last 1
    $null = $signal.LogInformation("Completed test worker $($WorkItem.Index).")
    $signal.SetResult([PSCustomObject]@{
        Index       = [int]$WorkItem.Index
        RuntimeId   = $Runtime.Id
        RunspaceId  = [runspace]::DefaultRunspace.InstanceId.ToString()
        ContextName = $Context.Name
        MemberWasReused = $memberWasReused
        SourceWasUnaffected = $sourceWasUnaffected
    })
    return $signal
}

function Test-STPoolErrorWorker {
    param(
        [object]$Runtime,
        [object]$WorkItem,
        [object]$Context
    )

    Write-Error "Requested test error for $($WorkItem.Index)." -ErrorAction Continue
    $signal = [Signal]::Start("TestErrorWorker:$($WorkItem.Index)") | Select-Object -Last 1
    $null = $signal.LogInformation("Worker $($WorkItem.Index) returned after writing an error.")
    $signal.SetResult([PSCustomObject]@{ Index = [int]$WorkItem.Index })
    return $signal
}

function Test-STPoolThrowWorker {
    param(
        [object]$Runtime,
        [object]$WorkItem,
        [object]$Context
    )

    throw "Requested test worker exception for $($WorkItem.Index)."
}

function Test-STPoolInvalidWorker {
    param(
        [object]$Runtime,
        [object]$WorkItem,
        [object]$Context
    )

    return [PSCustomObject]@{ Index = [int]$WorkItem.Index }
}

function Test-STBackgroundWorker {
    param(
        [object]$Runtime,
        [object]$WorkItem,
        [object]$Context
    )

    Start-Sleep -Milliseconds ([int]$WorkItem.DelayMilliseconds)
    $signal = [Signal]::Start("TestBackgroundWorker:$($WorkItem.Index)") | Select-Object -Last 1
    $null = $signal.LogInformation("Completed background worker $($WorkItem.Index).")
    $signal.SetResult([PSCustomObject]@{
        Index       = [int]$WorkItem.Index
        Value       = $WorkItem.Value
        ContextName = $Context.Name
    })
    return $signal
}

Export-ModuleMember -Function Initialize-STEnvironment, Test-STPoolWorker, Test-STPoolErrorWorker, Test-STPoolThrowWorker, Test-STPoolInvalidWorker, Test-STBackgroundWorker
