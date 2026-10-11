using module ../../SignalGraph/Src/PowerShell/SignalGraph.psd1

$ErrorActionPreference = 'Stop'
$foundationRoot = Join-Path $PSScriptRoot '../Src/PowerShell'
. "$foundationRoot/Utilities/Threading/STBackgroundTasks.ps1"
. "$foundationRoot/Utilities/Adapters/Condenser/Plan/Complete-PlanPhaseTask.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Add-CompletedTestTask([string]$TaskId, [string]$Key, [object]$Value) {
    $script:STBackgroundTasks[$TaskId] = [PSCustomObject]@{
        TaskId = $TaskId; TaskName = $TaskId; OwnerId = 'Test'; State = 'Completed'
        CreatedUtc = [DateTime]::UtcNow; StartedUtc = [DateTime]::UtcNow; CompletedUtc = [DateTime]::UtcNow
        CompletionEnvelope = [PSCustomObject]@{
            TaskId = $TaskId
            Failed = $false
            Error = $null
            InitializationSignal = $null
            WorkerSignal = [PSCustomObject]@{
                Name = 'Worker'; Meta = $null; Entries = @(); HasResult = $true
                Result = [PSCustomObject]@{
                    Completed = $true
                    ExportedResults = @([PSCustomObject]@{
                        Key = $Key; Name = "Export:$Key"; Meta = $null; HasResult = $true; Result = $Value
                    })
                }
            }
        }
        Error = $null; PowerShell = $null; Runspace = $null; Handle = $null
    }
}

$graph = ([Graph]::Start('ImportGraph', $null, $false) | Select-Object -Last 1).GetResult()
$itemSignal = [Signal]::Start('ImportItem') | Select-Object -Last 1
$null = $itemSignal.SetPointer($graph)
$parentSignal = [Signal]::Start('ImportParent') | Select-Object -Last 1

Add-CompletedTestTask -TaskId 'new-key' -Key 'AsyncResult' -Value ([PSCustomObject]@{ Value = 42 })
$newSignal = Complete-PlanPhaseTask -TaskId 'new-key' -ItemSignal $itemSignal -Signal $parentSignal -RemoveAfterReceive | Select-Object -Last 1
Assert-True (-not $newSignal.Failure()) 'A new returned key failed to import.'
Assert-True ($graph.Grid['AsyncResult'].GetResult().Value -eq 42) 'Imported result did not preserve its value.'
Assert-True (-not $script:STBackgroundTasks.ContainsKey('new-key')) 'Received task was not removed.'

$existingSignal = [Signal]::Start('Existing') | Select-Object -Last 1
$existingSignal.SetResult('Parent')
$null = $graph.RegisterSignal('Collision', $existingSignal)

Add-CompletedTestTask -TaskId 'preserve' -Key 'Collision' -Value 'Worker'
$preserveSignal = Complete-PlanPhaseTask -TaskId 'preserve' -ItemSignal $itemSignal -Signal $parentSignal -CollisionAction PreserveParent -RemoveAfterReceive | Select-Object -Last 1
Assert-True (-not $preserveSignal.Failure() -and $graph.Grid['Collision'].GetResult() -eq 'Parent') "PreserveParent did not retain the parent value (Failure=$($preserveSignal.Failure()), Value=$($graph.Grid['Collision'].GetResult())): $((@($preserveSignal.Entries | ForEach-Object Message)) -join ' | ')"

Add-CompletedTestTask -TaskId 'overwrite' -Key 'Collision' -Value 'Worker'
$overwriteSignal = Complete-PlanPhaseTask -TaskId 'overwrite' -ItemSignal $itemSignal -Signal $parentSignal -CollisionAction OverwriteParent -RemoveAfterReceive | Select-Object -Last 1
Assert-True (-not $overwriteSignal.Failure() -and $graph.Grid['Collision'].GetResult() -eq 'Worker') 'OverwriteParent did not import the worker value.'

Add-CompletedTestTask -TaskId 'error' -Key 'Collision' -Value 'Rejected'
$errorSignal = Complete-PlanPhaseTask -TaskId 'error' -ItemSignal $itemSignal -Signal $parentSignal -CollisionAction Error -RemoveAfterReceive | Select-Object -Last 1
Assert-True ($errorSignal.Failure() -and $graph.Grid['Collision'].GetResult() -eq 'Worker') 'Error collision policy did not reject the worker value.'

Write-Output 'PASS: explicit result imports, task removal, and collision policies.'
