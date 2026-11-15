param([Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)]$Selection,[string]$Cycle)
$ErrorActionPreference='Stop'
$native=$Selection.SignalGraph.Backend -eq 'Native'
$module=Get-Module SovereignTrust.Foundation
if(@($module).Count -ne 1){throw 'MIGRATION_MODULE_COUNT'}
$cases=& $module {
 param($Native)
 $results=[Collections.Generic.List[object]]::new()
 function AssertCase($Id,[scriptblock]$Check){try{& $Check;$results.Add([ordered]@{Id=$Id;Pass=$true})}catch{$results.Add([ordered]@{Id=$Id;Pass=$false;Error=$_.Exception.Message})}}
 function Failed($Value){if($Native){$Value.Failure()}else{$Value.Failure()}}
 function Require($Condition,$Message='Contract assertion failed'){if(-not $Condition){throw $Message}}
 $parent=Start-SignalWrapper -Name Migration.Focus
 foreach($case in @(
  @{Id='greater-fraction';Path='GT(1.2,1.1)';Expected=$true},
  @{Id='greater-negative';Path='GT(-1.1,-1.2)';Expected=$true},
  @{Id='greater-binary64-tie';Path='GT(9007199254740993,9007199254740992)';Expected=$false},
  @{Id='lesser-fraction';Path='LT(1.1,1.2)';Expected=$true},
  @{Id='lesser-source-decimal-string-rounding';Path='LT(0.1000000000000000000000000001,0.1000000000000000000000000002)';Expected=$false},
  @{Id='lesser-equal';Path='LT(1.2,1.2)';Expected=$false}
 )){AssertCase $case.Id {$r=Resolve-TokenDynamic -Signal $parent -Path $case.Path|Select-Object -Last 1;Require (-not (Failed $r) -and $r.GetResult() -is [bool] -and $r.GetResult() -eq $case.Expected) $case.Path}}
 foreach($path in 'GT(1)','LT(1,2,3)','GT(bad,1)'){AssertCase ('invalid-'+$path) {$r=Resolve-TokenDynamic -Signal $parent -Path $path|Select-Object -Last 1;Require (Failed $r)}}
 AssertCase 'order-double-category' {$r=[PlanCondenser]::ResolveIterationKey([double]1.25);Require ($r.Category -ceq 'Numeric' -and $r.Value.GetType() -eq [double] -and $r.Value -eq 1.25)}
 AssertCase 'order-decimal-normalizes-double' {$r=[PlanCondenser]::ResolveIterationKey([decimal]1.25);Require ($r.Value.GetType() -eq [double])}
 AssertCase 'order-binary64-stable-tie' {$a=[pscustomobject]@{Key=([PlanCondenser]::ResolveIterationKey([long]9007199254740993)).Value;Category='Numeric';Position=0};$b=[pscustomobject]@{Key=([PlanCondenser]::ResolveIterationKey([long]9007199254740992)).Value;Category='Numeric';Position=1};Require ([PlanCondenser]::CompareIterationKeys($a,$b,$false) -lt 0 -and [PlanCondenser]::CompareIterationKeys($a,$b,$true) -lt 0)}
 AssertCase 'order-null-last-both' {$a=[pscustomobject]@{Key=$null;Category=$null;Position=0};$b=[pscustomobject]@{Key=1;Category='Numeric';Position=1};Require ([PlanCondenser]::CompareIterationKeys($a,$b,$false) -gt 0 -and [PlanCondenser]::CompareIterationKeys($a,$b,$true) -gt 0)}
 $results.ToArray()
} $native
$failed=@($cases|Where-Object{-not $_.Pass})
$report=[ordered]@{Scope='Current two-file focused contracts';Backend=if($native){'NativeSG'}else{'LegacyPS'};PassCount=$cases.Count-$failed.Count;FailCount=$failed.Count;SkipCount=0;Total=$cases.Count;Cases=@($cases)}
$report|ConvertTo-Json -Depth 8|Set-Content (Join-Path $RunRoot 'migration-focused.json') -Encoding utf8NoBOM
if($failed.Count){throw ('MIGRATION_ASSERT: '+($failed.Id -join ','))}
$report
