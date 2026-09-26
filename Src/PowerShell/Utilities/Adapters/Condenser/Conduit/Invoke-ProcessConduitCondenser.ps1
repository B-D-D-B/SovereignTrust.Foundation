using module SignalGraph
# =============================================================================
# 📍 Invoke-ConduitCondenser (Declarative Graph Builder + Injector)
#  License: MIT License • Copyright (c) 2025 Silicon Dream Artists. Current copyright holder: BDDB LLC.
#  Authors: Shadow PhanTom ☠️🧁👾️/🤖 • Neural Alchemist ⚗️☣️🐲 • Last Generated: 06/25/2025
# =============================================================================
# This function performs a single declarative execution of a graph plan over a 
# scoped memory object, returning a wrapped Signal with a `.Pointer` to the 
# constructed graph. It is designed for use inside a recursive formula graph 
# condenser loop, and supports injection of the graph signal into a declared 
# memory wire path if `TargetWirePath` is specified.
#
# Inputs:
#   - ParentSignal: the governing signal scope (used for escalation and lineage)
#   - Plan: a GraphFormulaPlan containing Source/Sources/Target fields
#   - Item: the scoped JSON object or memory jacket to apply the plan against
#   - PlanName: the declared name of the plan (used for logging + signal identity)
#
# Process:
#   - Creates a scoped sub-signal with jacket and plan metadata
#   - Runs Resolve-PathGraphForJsonArray to generate graph
#   - Wraps result in a new Signal with .Pointer set
#   - Injects signal into memory if TargetWirePath is defined
#
# Output:
#   - Returns the wrapped Signal with .Pointer to the constructed graph
#

function Invoke-ProcessConduitCondenser {
    param (
        [Signal]$Signal,
        [object]$Plan,
        [Signal]$ItemSignal
    )

    $opSignal = [Signal]::Start("Invoke-ConduitCondenser:$($Plan.Name)", $Signal) | Select-Object -Last 1

    $SourceData = $ItemSignal.GetResult($true)
    $SupportParallelismSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "SupportParallelism" -Default $false | Select-Object -Last 1
    $SupportParallelism = $SupportParallelismSignal.GetResult()

    $SourceAdapterSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Adapter" | Select-Object -Last 1
    $SourceActivitySignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Activity" -Default "Read" -SignalLevel "Warning" | Select-Object -Last 1

    $SourceAdapter = $SourceAdapterSignal.GetResult()
    $SourceActivity = $SourceActivitySignal.GetResult()

    #    $mySignal = Remove-ReversePointersFromSignal -RootSignal $Signal
    #    $Signalx = $mySignal | ConvertTo-Json -Depth 100 

    if (-not $SupportParallelism -or $SourceData.Grid.Count -eq 1) {
        foreach ($item in $SourceData.Grid.GetEnumerator()) {
            if ($isFailed) {
                break
            }

            $plan = ($item.Value).HasResult() ? ($item.Value).GetResult() : $Plan
            $MappingResultSignal = Invoke-MappedAdapter `
                -Signal $Signal `
                -Adapter $SourceAdapter `
                -Activity $SourceActivity `
                -Plan $plan `
                -ItemSignal $item.Value
            | Select-Object -Last 1

            <#
            $cloneStatus = Resolve-PathFromDictionary -Dictionary $cloneStep -Path "Status"
            $Success = $cloneStatus -eq "Success" -or $innerStatus -eq "Skipped"

            $isFailed = $isFailed -or -not ($Success)

            $cloneStepErrorLog = Resolve-PathFromDictionary -Dictionary $cloneStep -Path "ErrorLog"
            if ($cloneStepErrorLog) {
                $ErrorLog += $cloneStepErrorLog
            }
#>
            if ($repeatDelayMS -gt 0) {
                $delay = Get-Random -Minimum ($repeatDelayMS / 2) -Maximum ($repeatDelayMS * 2)
                Start-Sleep -Milliseconds ([int]$delay)
            }
        }

        <#
        $Status = $Success ? "Success" : "Failed"    

        Add-PathToDictionary -Dictionary $nextStep -Path "Status" -Value $Status
        if ($ErrorLog.Count -gt 0) {
            Add-PathToDictionary -Dictionary $nextStep -Path "ErrorLog" -Value $ErrorLog
        }
            #>
    }
    else {
        # Within-set parallelism; honor per-set throttle
        #    $environment = Resolve-PathFromDictionary -Dictionary $Context -Path "Environment"
        #  $maxParallel = if ($nextStep.MaxParallelism) { [int]$nextStep.MaxParallelism } else { $environment.DefaultMaxParallelism ?? 4 }
        $maxParallel = 1
        
        $resultSignal = Invoke-ConduitPool -Signal $ConductionSignal -Plan $Plan -ItemSignal $ItemSignal
        
        $isFailed = $false
        $indices = 0..($SourceData.Grid.Count - 1)
        $values = $SourceData.Grid.Values
        $item = $values[0]

        $values = $SourceData.Grid.Keys
        $item = $values[0]

        
        $isSuccessArray = $indices | ForEach-Object -Parallel {
            if ($using:isFailed) {
                break
            } 

            $myvalues = $using:SourceData.Grid.Values
            $myvalues = @($using:SourceData.Grid.Values)
            $values = $using:values
            $item = $values[$_]
. "$PSScriptRoot\..\..\..\SovereignTrust.Foundation\Src\PowerShell\Classes\Adapters\Telemetry\SignalTelemeter.ps1"
            . "$PSScriptRoot\..\..\..\SovereignTrust.Foundation\Src\PowerShell\Classes\Adapters\Telemetry\ConsoleLogger.ps1"
            $isnull = ($item -eq $null)
            Import-Module ../SovereignTrust.Foundation/Src/PowerShell/SovereignTrust.Foundation.psd1 -Force 
            Write-Host $using:SourceActivity
            Write-Host $using:Signal.Name
            Write-Host $using:Plan.Name
            Write-Host $_
            Write-Host ($myvalues[$_].Name) 
            Write-Host ($myvalues.GetType())
            Write-Host $isnull
            Write-Host $item #-is [Signal])
            Write-Host $using:SourceAdapter

            #Write-Host $using:SourceData.Grid.Values

            #$r = Resolve-PathFromDictionary -Dictionary $using:SourceData -Path "#.$($item).Name" | Select-Object -Last 1
            #Write-Host $r.GetResult()
            #Write-Host $r.HasResult()

            <#
#>
            $MappingResultSignal = Invoke-MappedAdapter `
                -Adapter $using:SourceAdapter `
                -Activity $using:SourceActivity `
                -Plan $using:Plan `
                -ItemSignal $myvalues[$_]
            | Select-Object -Last 1

            Write-Host $MappingResultSignal

            <#

$MappingResultSignal = Invoke-MappedAdapter `
                -Signal $using:Signal `
                -Adapter $using:SourceAdapter `
                -Activity $using:SourceActivity `
                -Plan $using:Plan `
                -ItemSignal $myvalues[$_]
            | Select-Object -Last 1

            Write-Host $MappingResultSignal
<#
#>

            <#
            $cloneStatus = Resolve-PathFromDictionary -Dictionary $cloneStep -Path "Status"
            $Success = $cloneStatus -eq "Success" -or $cloneStatus -eq "Skipped"

            # TODO: Fix potential multi-threaded race condition of overwriting another ErrorLog or isFailed status
            $isFailed = $isFailed -or -not ($Success)

            $cloneStepErrorLog = Resolve-PathFromDictionary -Dictionary $cloneStep -Path "ErrorLog"
            if ($cloneStepErrorLog) {
                $ErrorLog += $cloneStepErrorLog
            }

            if ($using:repeatDelayMS -gt 0) {
                $delay = Get-Random -Minimum ($using:repeatDelayMS / 2) -Maximum ($using:repeatDelayMS * 2)
                Start-Sleep -Milliseconds ([int]$delay)
            }
            #>
            # TODO: change to return error log
            return -not $using:isFailed
        } -ThrottleLimit $maxParallel

        $isFailed = $isSuccessArray -contains $false
        $Status = $isFailed ? "Failed" : "Success"
        Add-PathToDictionary -Dictionary $nextStep -Path "Status" -Value $Status
    }
                
    # TODO: Change result to something meaningful or not at all.
    $opSignal.SetResult($ItemSignal)
    $opSignal.LogInformation("✅ Graph plan '$PlanName' completed successfully.")
    return $opSignal
}
