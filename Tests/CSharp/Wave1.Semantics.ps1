param([Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)]$Selection)
$ErrorActionPreference='Stop'
# Parsed only after the launcher's exact selected modules are loaded.
$module=Get-Module SovereignTrust.Foundation
& $module {
    param($RunRoot,$TestScript,$Selection)
    $cases=[Collections.Generic.List[object]]::new()
    function Check($Id,[bool]$Condition,$Value) {
        $cases.Add([ordered]@{Id=$Id;Pass=$Condition;Value=$Value})
        $cases.ToArray()|ConvertTo-Json -Depth 14|Set-Content (Join-Path $RunRoot 'assertions.json') -Encoding utf8NoBOM
    }
    foreach($case in @(
        @{Id='false';Value=$false;Type='System.Boolean';Present=$true},
        @{Id='zero';Value=0;Type='System.Int32';Present=$true},
        @{Id='empty';Value='';Type='System.String';Present=$true},
        @{Id='null';Value=$null;Type=$null;Present=$false}
    )) {
        $s=[Signal]::Start($case.Id)|Select-Object -Last 1
        $s.SetResult($case.Value)
        $v=$s.GetResult();$type=if($null -ne $v){$v.GetType().FullName}else{$null}
        Check "value.$($case.Id)" ($s.HasResult() -eq $case.Present -and $type -eq $case.Type -and $v -ceq $case.Value) @{Type=$type;Present=$s.HasResult();Value=$v}
    }
    $missing=[Signal]::Start('missing')|Select-Object -Last 1
    Check 'value.missing' (-not $missing.HasResult()) $false
    foreach($n in 0,1,3){
        $array=[object[]]::new($n);for($i=0;$i -lt $n;$i++){$array[$i]=$i}
        $s=[Signal]::Start('array')|Select-Object -Last 1;$s.SetResult($array);$v=$s.GetResult()
        Check "array.$n" ($v -is [object[]] -and $v.Count -eq $n -and $s.HasResult()) @{Count=$v.Count;Type=$v.GetType().FullName;Values=$v}
    }
    $warning=[Signal]::Start('warning')|Select-Object -Last 1;$null=$warning.LogWarning('wave1 warning')
    $critical=[Signal]::Start('critical')|Select-Object -Last 1;$null=$critical.LogCritical('wave1 critical')
    $merge=[Signal]::Start('merge')|Select-Object -Last 1;$null=$merge.MergeSignal(@($warning,$critical))
    Check 'severity.merge' ($merge.Failure() -and $merge.Level -ceq 'Critical') @{Level=$merge.Level;Failure=$merge.Failure()}
    $g=([Graph]::Start('Wave1',$null,$false)|Select-Object -Last 1).GetResult()
    $s=[Signal]::Start('Member')|Select-Object -Last 1;$s.SetResult([pscustomobject]@{Count=1})
    $null=$s.SetPointer($g);$s.SetControl($s);$null=$s.SetJacket($s)
    $null=$g.RegisterSignal('Member',$s)
    Check 'graph.references' ([object]::ReferenceEquals($s.GetPointer(),$g) -and [object]::ReferenceEquals($s.GetControl(),$s) -and [object]::ReferenceEquals($s.GetJacket(),$s)) $true
    $g.Grid['member'].GetResult().Count=2
    Check 'graph.case.shared' ($g.Grid.Count -eq 1 -and $s.GetResult().Count -eq 2) @{Count=$s.GetResult().Count;Keys=@($g.GetKeys())}
    # Missing PS helpers are documented native repairs, not a successful PS oracle.
    # Retain both required IDs and immutable historical failures without PASS.
    . (Join-Path (Split-Path $TestScript) 'Assert-Wave1SourceCapability.ps1')
    $classification=Assert-STWave1SourceCapability -Selection $Selection -TestRoot (Split-Path $TestScript)
    foreach($id in $classification.Labels) {
        $cases.Add([ordered]@{Id=$id;Pass=$null;Status='KnownUnsupportedSource';FixtureId=$classification.FixtureId;RequiredNativeCase=$id;EvidenceSha256=$classification.ManifestSha256;HistoricalReceipts=$classification.HistoricalReceipts})
    }
    $dictionary=@([pscustomobject]@{Name='Key';Value=0},[pscustomobject]@{Name='key';Value=$false})|Convert-ToDictionary -ValueProperty Value
    Check 'dictionary.case.overwrite' ($dictionary.Count -eq 1 -and $dictionary['KEY'] -is [bool] -and $dictionary['KEY'] -eq $false) @{Count=$dictionary.Count;Value=$dictionary['KEY']}
    $item=[Signal]::Start('Item')|Select-Object -Last 1;$null=$item.SetPointer($g)
    $item.SetResult(@([pscustomobject]@{Name='InnerStep';Activity='Fixture'}))
    $conduction=[Signal]::Start('Conduction')|Select-Object -Last 1;$null=$conduction.SetPointer($g)
    $plan=[pscustomobject]@{Name='NamedParentPhase';Path='@';Config=[pscustomobject]@{Iteration=0;PreventReclone=$false;Break=$false;SkipRename=$true}}
    # Controlled downstream dispatch is explicit; actual selected Plan/Phase code runs.
    $script:wave1Calls=0;$script:wave1Phase=$null
    function Invoke-CondenserAdapter {
        param($Slot,$Activity,$Signal,$Plan,$ItemSignal)
        $result=[Signal]::Start("Fixture.$Slot.$Activity")|Select-Object -Last 1
        if($Slot -ceq 'Hydration'){$result.SetResult($ItemSignal.GetJacketResult())}
        elseif($Slot -ceq 'Memory' -and $Activity -ceq 'Generate'){
            $script:wave1Calls++;$script:wave1Phase=$Plan
            $null=$ItemSignal.GetPointer().RegisterResultAsSignal('PhaseEffect','controlled');$result.SetResult($true)
        }else{$null=$result.LogCritical("Unexpected controlled dispatch $Slot/$Activity")}
        return $result
    }
    Start-STExecutionTrace -Context @{RunId='wave1';CaseId='copy-plan';CorrelationId='fixture';Sources=@{Plan=@{Path=$TestScript;Sha256=(Get-FileHash -LiteralPath $TestScript).Hash;Location='NamedParentPhase'}}}
    try{
        $result=[PlanCondenser]::new().Invoke('','InvokePhase',$conduction,$plan,$item)
        Check 'plan.selected.phase' (-not $result.Failure() -and $script:wave1Calls -eq 1 -and $script:wave1Phase.Name -ceq 'NamedParentPhase' -and @($script:wave1Phase.Steps).Count -eq 1 -and $g.Grid['PhaseEffect'].GetResult() -ceq 'controlled') @{Calls=$script:wave1Calls;Phase=$script:wave1Phase.Name;Steps=@($script:wave1Phase.Steps).Count;Effect=$g.Grid['PhaseEffect'].GetResult()}
        $trace=Get-STExecutionTrace;$children=@($trace.Rows|Where-Object BoundaryKind -CEQ 'Phase')
        Check 'plan.trace' ($trace.Complete -and @($trace.Rows).Count -eq 2 -and $children.Count -eq 1 -and $children[0].BoundaryName -ceq 'NamedParentPhase' -and $children[0].Status -ceq 'Succeeded') @{Rows=@($trace.Rows).Count;Child=$children[0].BoundaryName;Status=$children[0].Status}
        $trace|ConvertTo-Json -Depth 20|Set-Content (Join-Path $RunRoot 'plan-trace.json') -Encoding utf8NoBOM
    }finally{Stop-STExecutionTrace}
    $storage=Join-Path $RunRoot 'storage';$null=[IO.Directory]::CreateDirectory($storage)
    $write=Invoke-EmbeddedFileSystem_WriteObject -Signal $conduction -Content ([pscustomobject]@{Marker='complete';Values=@($false,0,'')}) -VirtualPath 'value.json' -Addresses @($storage)|Select-Object -Last 1
    $read=Invoke-EmbeddedFileSystem_ReadObject -Signal $conduction -VirtualPath 'value.json' -Addresses @($storage)|Select-Object -Last 1
    $raw=[IO.File]::ReadAllText((Join-Path $storage 'value.json'))
    $returned=$read.GetResult();$content=$returned|ConvertFrom-Json
    Check 'storage.local.write.read' (-not $write.Failure() -and $write.HasResult() -and $write.GetResult() -is [string] -and $write.GetResult() -ceq (Join-Path $storage 'value.json') -and -not $read.Failure() -and $read.HasResult() -and $returned -is [string] -and $returned -ceq $raw -and $content.Marker -ceq 'complete' -and $content.Values.Count -eq 3 -and $content.Values[0] -is [bool] -and $content.Values[1] -is [long] -and $content.Values[1] -eq 0 -and $content.Values[2] -is [string] -and $content.Values[2] -ceq '') @{Marker=$content.Marker;Values=$content.Values;ReadType=$returned.GetType().FullName;WriteType=$write.GetResult().GetType().FullName}
    $delete=Invoke-EmbeddedFileSystem_DeleteObject -Signal $conduction -VirtualPath 'value.json' -Addresses @($storage)|Select-Object -Last 1
    $exists=Invoke-EmbeddedFileSystem_ExistsObject -Signal $conduction -VirtualPath 'value.json' -Addresses @($storage)|Select-Object -Last 1
    Check 'storage.local.delete.exists' (-not $delete.Failure() -and $delete.GetResult() -eq $true -and -not $exists.Failure() -and $exists.GetResult() -is [bool] -and $exists.GetResult() -eq $false) @{Delete=$delete.GetResult();Exists=$exists.GetResult()}
    $supported=@($cases|Where-Object {$_.Pass -is [bool]})
    $unsupported=@($cases|Where-Object {$_.Contains('Status') -and $_.Status -ceq 'KnownUnsupportedSource' -and $null -eq $_.Pass})
    if($supported.Count -ne 16 -or $unsupported.Count -ne 2 -or $cases.Count -ne 18 -or @($unsupported.Id|Sort-Object) -join ',' -cne 'graph.cycle.roundtrip,graph.roundtrip'){throw 'ST_WAVE1_CASE_INVENTORY: expected16 supported and2 named KnownUnsupportedSource cases'}
    $failed=@($supported|Where-Object {$_.Pass -eq $false})
    $receipt=[pscustomobject]@{Backend='PowerShell';Scope='Supported copied-tree PS parity only';Command=[Environment]::GetCommandLineArgs();Cases=$cases.ToArray();Count=$cases.Count;SupportedCount=$supported.Count;SupportedPassCount=($supported.Count-$failed.Count);SupportedFailCount=$failed.Count;SkipCount=0;KnownUnsupportedSourceCount=$unsupported.Count;RequiredNativeCases=@($unsupported.RequiredNativeCase);ClassificationEvidence=$classification;Pass=($failed.Count -eq 0);ControlledPlanDownstream=$true;NativeStorageIntegration=$false}
    $receipt|ConvertTo-Json -Depth 16|Set-Content (Join-Path $RunRoot 'semantic-result.json') -Encoding utf8NoBOM
    if($failed.Count){throw "ST_WAVE1_ASSERT: $($failed.Id -join ',')"}
    $receipt
} $RunRoot $PSCommandPath $Selection
