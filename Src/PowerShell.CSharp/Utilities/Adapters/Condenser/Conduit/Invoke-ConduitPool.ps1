# Minimal RunspacePool pattern:
# - shared $WorkDict (id -> work item)
# - each work item has its own Signal for telemetry
# - each runspace ONLY mutates its own work item
# - merge step runs single-thread afterwards

# NOTE: This assumes your Signal class is already loaded.

function Invoke-ConduitPool {
    [CmdletBinding()]
    param(
        [SignalGraph.Signal]$Signal,
        [object]$Plan,
        [SignalGraph.Signal]$ItemSignal,

        [object]$Conductor,

        [int]$MaxThreads = 6
    )

    $opSignal = [SignalGraph.Signal]::Start("Invoke-WorkItemsInRunspacePool", $Signal) | Select-Object -Last 1

    $WorkDict = $ItemSignal.GetResult($true).Grid
    $MaxThreads = 4
    <#
    # Ensure each work item has its own Signal up front (no shared Entries lists)
    foreach ($id in @($WorkDict.Keys)) {
        $item = $WorkDict[$id]
        if ($null -eq $item) { continue }

        if ($null -eq $item.Signal) {
            $item.Signal = [SignalGraph.Signal]::Start("WorkItem:$id", $Conductor)
        }
        $item.State  = "Queued"
        $item.Error  = $null jjjjjjj
    }
#>

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $selectedWorker = Get-STWorkerSelection
    if ($null -ne $selectedWorker) { $iss = New-STSelectedInitialSessionState -Selection $selectedWorker }
    else { $iss.ImportPSModule(@([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../SovereignTrust.Foundation.psd1')))) }

    # Create and open a runspace pool (same process, no serialization barrier)
    $pool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads, $iss, $Host)
    $pool.ApartmentState = 'MTA'
    $pool.ThreadOptions = 'ReuseThread'
    $pool.Open()

    $jobs = New-Object System.Collections.Generic.List[object]

                            if (Get-Command Resolve-PathFromDictionary -CommandType Function -ErrorAction SilentlyContinue) {
                            $ItemSignal.LogInformation("Function exists")
                        }

                                                    if (Get-Command Resolve-PathFromDictionaryX -CommandType Function -ErrorAction SilentlyContinue) {
                            $ItemSignal.LogInformation("Function exists")
                        }

    try {
        foreach ($id in @($WorkDict.Keys)) {

            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            
            $_ItemSignal = $WorkDict[$id]

            $_ItemSignal.LogInformation("▶️ Check before Running work item '$id'.")

            $null = $ps.AddScript({
                    #                    param($ConductionSignal, $ItemSignal, $Plan, $ItemName)
                    param($ItemSignal, $ItemName, $ScriptRoot)#, $Plan, $ConductionSignal)

                    if ($null -ne $STWorkerSelection) { Assert-STFoundationSelection -Selection $STWorkerSelection -RequireLoaded }
                    #$OpSignal.LogInformation("✅ Completed work item '$ItemName'.")
                    if ($ItemSignal) {
                        $ItemSignal.LogInformation("▶️ Running work item '$ItemName'.")
                    }

                    #Wait-Debugger

                    try {
                        $ItemSignal.LogInformation("🔥 Work item '$ItemName' Test exception")

                        if (Get-Command Resolve-PathFromDictionary -CommandType Function -ErrorAction SilentlyContinue) {
                            $ItemSignal.LogInformation("Function exists")
                        }
                        else {
                            $ItemSignal.LogInformation("Function does not exist")                            
                        }
                        #                       $SourceAdapterSignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Adapter" | Select-Object -Last 1
                        #                      $SourceActivitySignal = Resolve-PathFromDictionary -Dictionary $Plan -Path "Activity" -Default "Read" -SignalLevel "Warning" | Select-Object -Last 1

                        #                     $SourceAdapter = $SourceAdapterSignal.GetResult()
                        #                    $SourceActivity = $SourceActivitySignal.GetResult()





                        #                   $ItemSignal.LogCritical("🔥 SourceAdapter: '$SourceAdapter'")
                        #                  $ItemSignal.LogCritical("🔥 SourceActivity: '$SourceActivity'")
                        # ---- Do your work here ----
                        # Example: access adapters via $Conductor, but don't mutate shared conductor graph here.
                        # $adapter = $Conductor.Adapters.Content  # (example; use your real access pattern)
                        # $data = Invoke-StorageAdapter ... etc

                        # Write ONLY to this item
                        #$ItemSignal.Result = $computed
                        #$ItemSignal.State  = "Completed"
                        #  $ItemSignal.LogInformation("✅ Completed work item '$ItemName'.")
                    }
                    catch {
                        #$item.State = "Failed"
                        #$ItemSignal.Error = "$_"
                        $ItemSignal.LogInformation("🔥 Work item '$ItemName' failed: $_")
                    }
                }).AddParameters(@{
                    ItemSignal = $_ItemSignal
                    ItemName   = $id
                    ScriptRoot = $PSScriptRoot
      #              Plan       = $Plan
                    #                    ConductionSignal = $Signal
                })

            $handle = $ps.BeginInvoke()

            $jobs.Add([pscustomobject]@{
                    Id         = $id
                    ItemSignal = $_ItemSignal
                    PS         = $ps
                    Handle     = $handle
                }) | Out-Null
        }

        # Wait for all workers        
        $hasJobs = $true
        $lastJobs = $jobs
        while ($hasJobs) {
            $hasJobs = $false
            $myJ = $jobs
            $remainingJobs = New-Object System.Collections.Generic.List[object]
            foreach ($job in $lastJobs) {
                if (-not $job.Handle.IsCompleted) {
                    $hasJobs = $true
                    $remainingJobs.Add($job)
                }
                else {
                    try { $null = $job.PS.EndInvoke($job.Handle) } catch { }
                    try { $job.PS.Dispose() } catch { }
                }

            }

            if ($hasJobs) {
                $lastJobs = $remainingJobs
                Start-Sleep -Seconds 1
            }
        }
    }
    catch {
        $opSignal.LogCritical("Exception during conduction condenser run: $($_.Exception.Message)", $null, $_.Exception)
    }
    finally {
        try { $pool.Close() } catch { }
        try { $pool.Dispose() } catch { }
    }

    # Single-thread merge step (deterministic)
    $completed = 0
    $failed = 0

    foreach ($id in @($WorkDict.Keys | Sort-Object)) {
        $item = $WorkDict[$id]
        if ($null -eq $item) { continue }

        switch ($item.State) {
            "Completed" { $completed++ }
            "Failed" { $failed++ }
        }

        # Optional: Merge worker telemetry into the operation signal deterministically
        if ($item.Signal -is [SignalGraph.Signal]) {
            $opSignal.MergeSignal(@($item.Signal)) | Out-Null
        }

        # Optional: apply results to canonical memory here (single writer)
        # e.g., Add-PathToDictionary -Dictionary $SomeRoot -Path $item.TargetPath -Value $item.Result ...
    }

    $opSignal.LogInformation("🧾 RunspacePool finished. Completed=$completed Failed=$failed Total=$($WorkDict.Count)")
    if ($failed -gt 0) { $opSignal.LogWarning("One or more work items failed.") }

    $opSignal.SetResult([pscustomobject]@{
            Completed = $completed
            Failed    = $failed
            Total     = $WorkDict.Count
        })

    return $opSignal
}

# ---------------------------
# Minimal example work dict
# ---------------------------
# $work = [System.Collections.Specialized.OrderedDictionary]::new()
# $work["A"] = [pscustomobject]@{ Id="A"; Signal=$null; State=$null; Result=$null; Error=$null }
# $work["B"] = [pscustomobject]@{ Id="B"; Signal=$null; State=$null; Result=$null; Error=$null }
# $resultSignal = Invoke-WorkItemsInRunspacePool -WorkDict $work -Conductor $Conductor -MaxThreads 6 | Select-Object -Last 1
