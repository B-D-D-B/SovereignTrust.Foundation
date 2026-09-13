function Invoke-ST {
    [CmdletBinding()]
    param (
        [object]$Environment,
        [object]$ConductionPlanRoute,
        [object]$ConductionContext
    )

    function Invoke-PlanWithOptionalContext {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)]
            [Signal]$Signal,   # Signal with Conductor.Signal in Jacket

            [Parameter(Mandatory)]
            [object]$Overlay
        )

        $opSignal = [Signal]::Start("Invoke-ST: Conduction Runner", $Signal) | Select-Object -Last 1
        
        # Acts as the Conduction Signal with the Conductor
        $opSignal.SetControl($Signal)
        $opSignal.LogInformation("Resolving ConductionPlanRoute from RouteOverlay.")

        # ──────────────────────────────────────────────────────────────────────
        # Base mapping (overlay expected to provide name/path)
        # ──────────────────────────────────────────────────────────────────────
        $ConductionPlanMapping = [pscustomobject]@{
            Adapter   = 'Storage.Content'
            Activity  = 'Read'
            Container = 'Plans'
            Format    = 'Json'
            Key       = 'Plans'
        }

        # ──────────────────────────────────────────────────────────────────────
        # Merge overlay plan source (required)
        # ──────────────────────────────────────────────────────────────────────
        $mergeSignal = Invoke-TransformCondenser `
            -Activity 'Merge' `
            -Signal $opSignal.GetControl() `
            -Base $ConductionPlanMapping `
            -Overlay $Overlay `
            -MergeArrayHandling "Merge" `
        | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure(@($mergeSignal))) {
            $opSignal.LogCritical("Failed to merge RouteOverlay into ConductionPlanMapping.")
            return $opSignal
        }

        $ConductionPlanMapping = $mergeSignal.GetResult()

        $DisabledMapping = [PSCustomObject]@{
            Name              = "Bytes Me"
            IsEnabled = $false
        }

        $InvokeConductionMapping = [PSCustomObject]@{
            Name              = "Process Grid"
            Description       = "Uses the Conduit to run a Condenser.Conduction  on each item in the Graph made from previous step."
            Adapter           = "Condenser.Conduit"
            Activity          = "Process"
            ForEachPath       = "*"

            ForEachInTemplate = "*"
            ForEachIn         = ""

            ForEachAdapter    = "Condenser.Conduction"
            ForEachActivity   = "ST"
            SourceFormat      = "Json"
        }


        # ──────────────────────────────────────────────────────────────────────
        # Wrap as Memory.Generate plan
        # ──────────────────────────────────────────────────────────────────────
        $ConductionPlan = [pscustomobject]@{
            ReturnItemSignal = $true
            Steps         = @($DisabledMapping, $ConductionPlanMapping, $InvokeConductionMapping)
        }

        # ──────────────────────────────────────────────────────────────────────
        # Execute Memory.Generate
        # ──────────────────────────────────────────────────────────────────────
        $TargetSignal = [Signal]::Start("Invoke-PlanWithOptionalContext", $opSignal) | Select-Object -Last 1

        $sourceSignal = Invoke-CondenserAdapter `
            -Slot "Memory" `
            -Activity "Generate" `
            -Signal $opSignal.GetControl() `
            -Plan $ConductionPlan `
            -ItemSignal $TargetSignal `
        | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure(@($sourceSignal))) {
            $opSignal.LogCritical("Memory.Generate failed while resolving ConductionPlan.")
            return $opSignal
        }

        $opSignal.SetResult($sourceSignal.GetResult())
        $opSignal.LogInformation("✅ Conduction plan resolved successfully.")
        return $opSignal
    }


    function Resolve-PlanContentGeneration {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)]
            [Signal]$Signal,   # Signal with Conductor.Signal in Jacket

            [Parameter(Mandatory)]
            [object]$Overlay,

            # When true, run the merged content as a mapping through the Memory -> Generate condenser.
            [bool]$GenerateMemory
        )

        $opSignal = [Signal]::Start("Resolve-ConductionPlanRoute", $Signal) | Select-Object -Last 1

        $opSignal.LogInformation("🧭 Resolving ConductionPlanRoute from RouteOverlay.")

        # ──────────────────────────────────────────────────────────────────────
        # Base mapping (overlay expected to provide name/path)
        # ──────────────────────────────────────────────────────────────────────
        $ConductionPlanMapping = [pscustomobject]@{
            SourceAdapter   = 'Storage.Content'
            SourceActivity  = 'Read'
            SourceContainer = 'Plans'
            SourceFormat    = 'Json'
        }

        # ──────────────────────────────────────────────────────────────────────
        # Merge overlay (required)
        # ──────────────────────────────────────────────────────────────────────
        $mergeSignal = Invoke-TransformCondenser `
            -Activity 'Merge' `
            -Signal $Signal `
            -Base $ConductionPlanMapping `
            -Overlay $Overlay `
            -MergeArrayHandling "Merge" `
        | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure(@($mergeSignal))) {
            $opSignal.LogCritical("Failed to merge RouteOverlay into ConductionPlanMapping.")
            return $opSignal
        }

        $ConductionPlanMapping = $mergeSignal.GetResult()

        if (-not $GenerateMemory) {
            $opSignal.SetResult($mergeSignal.GetResult($true))
            return $opSignal
        }
        # ──────────────────────────────────────────────────────────────────────
        # Wrap as Memory.Generate plan
        # ──────────────────────────────────────────────────────────────────────
        $ConductionPlan = [pscustomobject]@{
            ReturnItemSignal = $true
            Steps         = @($ConductionPlanMapping)
        }

        # ──────────────────────────────────────────────────────────────────────
        # Execute Memory.Generate
        # ──────────────────────────────────────────────────────────────────────
        $TargetSignal = [Signal]::Start("Resolve-ConductionPlanRoute.Target", $opSignal) | Select-Object -Last 1

        $sourceSignal = Invoke-CondenserAdapter `
            -Slot "Memory" `
            -Activity "Generate" `
            -Signal $Signal `
            -Plan $ConductionPlan `
            -ItemSignal $TargetSignal `
        | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure(@($sourceSignal))) {
            $opSignal.LogCritical("Memory.Generate failed while resolving ConductionPlan.")
            return $opSignal
        }
        <#
        # Extract resolved plan
        $planSignal = Resolve-PathFromDictionary `
            -Dictionary $sourceSignal `
            -Path "@.*.#.Plan" `
            -SignalLevel "Critical" `
        | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure(@($planSignal))) {
            $opSignal.LogCritical("Failed to resolve '@.*.#.Plan' from Memory.Generate result.")
            return $opSignal
        }

        $opSignal.SetResult($planSignal.GetResult())
#>
        $opSignal.SetResult($sourceSignal.GetResult())
        $opSignal.LogInformation("✅ Conduction plan resolved successfully.")
        return $opSignal
    }

    function Resolve-ConductionContext {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)]
            [Signal]$Signal,

            [object]$ConductionContext,
            [object]$ConductionContextOverlay
        )

        # ░▒▓█ SIGNAL START █▓▒░
        $opSignal = [Signal]::Start("Resolve-ConductionContext", $Signal) | Select-Object -Last 1

        try {
            $opSignal.LogInformation("🧭 Resolving ConductionContext.")

            # Start from provided context if present, otherwise an empty object
            $context = if ($null -ne $ConductionContext) { $ConductionContext } else { [PSCustomObject]@{} }

            # Apply overlay if provided
            if ($null -ne $ConductionContextOverlay) {
                $opSignal.LogInformation("🧩 Applying ConductionContextOverlay (Transform.Merge).")

                $mergeSignal = Invoke-TransformCondenser `
                    -Signal $Signal `
                    -Activity "Merge" `
                    -Base $context `
                    -Overlay $ConductionContextOverlay `
                    -MergeArrayHandling "Merge" `
                | Select-Object -Last 1

                if ($opSignal.MergeSignalAndVerifyFailure(@($mergeSignal))) {
                    $opSignal.LogCritical("Failed merging ConductionContextOverlay into ConductionContext.")
                    return $opSignal
                }

                $context = $mergeSignal.GetResult()
            }
            else {
                $opSignal.LogInformation("ℹ️ No ConductionContextOverlay provided; using base ConductionContext as-is.")
            }

            $opSignal.SetResult($context)
            $opSignal.LogInformation("✅ ConductionContext resolved successfully.")
            return $opSignal
        }
        catch {
            $opSignal.LogCritical("Exception in Resolve-ConductionContext: $($_.Exception.Message)", $null, $_)
            return $opSignal
        }
    }

    # ░▒▓█ START WRAPPER SIGNAL █▓▒░
    $opSignal = [Signal]::Start("Start-SovereignTrust") | Select-Object -Last 1

    $runtimeSignal = Initialize-STEnvironment -Environment $Environment -ParentSignal $opSignal | Select-Object -Last 1
    if ($opSignal.MergeSignalAndVerifyFailure(@($runtimeSignal))) {
        return $opSignal
    }
    if (-not $runtimeSignal.HasResult()) {
        $null = $opSignal.LogCritical("Environment initialization did not return a runtime.")
        return $opSignal
    }

    $runtime = $runtimeSignal.GetResult()
    $environmentSignal = $runtime.EnvironmentSignal
    $conductorSignal = $runtime.ConductorSignal
    $conductorJacketSignal = $runtime.ConductorJacketSignal
    $opSignal = $runtime.ConductionSignal
    $opSignal.Name = "Invoke-ST: Processor"
    $opSignal.LogInformation("Resolving ConductionPlanRoute from RouteOverlay.")


    $opSignal.AddProperty("SignalType", "Conductor")
    $processIdSignal = Resolve-PathFromDictionary -Dictionary $conductorSignal -Path "@.Config.Process.Id" | Select-Object -Last 1
    $processorIdSignal = Resolve-PathFromDictionary -Dictionary $conductorSignal -Path "@.Config.Process.ProcessorId" | Select-Object -Last 1

    $opSignal.AddProperty("ProcessorId", $processorIdSignal.GetResult())
    $opSignal.AddProperty("ProcessId", $processIdSignal.GetResult())
    $opSignal.AddProperty("OperationId", $processIdSignal.GetResult())
    $opSignal.AddProperty("State", "Started")
    $opSignal.AddProperty("StartedAt", [DateTime]::UtcNow)

    Invoke-Telemetry -Signal $opSignal -ItemSignal $opSignal

    <# TODO: Move or delete #> <#
    function TestTelemetry([object]$conductorJacketSignal) {
        $testOpSignal = [Signal]::Start("🎯 Start TestOpSignal", $environmentSignal) | Select-Object -Last 1
        $testOpSignal.AddTag("Mine")
        $testOpSignal.AddProperty("SignalId", ([guid]::NewGuid().ToString()))
        $testOpSignal.LogInformation("✅ Test Information Level");

        $entry = $testOpSignal.Entries | Select-Object -Last 1
        $entry.AddTag("Verbose")
        $entry.AddTag("IngestionScheduled")
        $entry.AddProperty("SignalId", ([guid]::NewGuid().ToString()))

        $testOpSignal.LogWarning("Test Warning Level");
        $entry = $testOpSignal.Entries | Select-Object -Last 1
        $entry.AddTag("Verbose")

        $testOpSignal.LogCritical("Test Critical Level", @("Verbose"));

        $signalMetaData = [PSCustomObject]@{
            OperationId = [guid]::NewGuid().ToString()
        }

        $testOpSignal.SetMeta($signalMetaData)

        try {    
         
            not-real-function
        }
        catch {
            $testOpSignal.LogCritical("Exception in Invoke-ST: $($_.Exception.Message)", @("Urgent"), $_)
        }

        Invoke-Telemetry -Signal $conductorJacketSignal -ItemSignal $testOpSignal
    }

    TestTelemetry -conductorJacketSignal $conductorJacketSignal
    <##>

    $conductionPlanRouteSignal = $null
    if ($ConductionPlanRoute) {
        $conductionPlanRouteSignal = Invoke-PlanWithOptionalContext -Signal $conductorJacketSignal -Overlay $ConductionPlanRoute  | Select-Object -Last 1


        $entryFilterSignal = [Signal]::Start("EntryFilter", $null) | Select-Object -Last 1
        $entryFilterSignal.MergeSignal($opSignal, $null, "Skip")

        $opSignal.Entries = $entryFilterSignal.Entries
        $opSignal.MergeSignal($conductionPlanRouteSignal, $null, "Skip")
        $opSignal.AddProperty("State", "Completed")
        $opSignal.AddProperty("EndedAt", [DateTime]::UtcNow)
        $opSignal.ModifiedDate = Get-Date
        Invoke-Telemetry -Signal $opSignal -ItemSignal $opSignal

        #    Invoke-Telemetry -Signal $conductorJacketSignal -ItemSignal $conductionPlanRouteSignal
    }

    return $opSignal
}
