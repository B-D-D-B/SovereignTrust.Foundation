param([Parameter(Mandatory)][string]$NativeDirectory,[Parameter(Mandatory)][string]$Receipt)
$ErrorActionPreference='Stop'
if(Test-Path $Receipt){throw 'ABI receipt must be new'}
[void][Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath((Join-Path $NativeDirectory Microsoft.Extensions.Logging.Abstractions.dll))
[void][Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath((Join-Path $NativeDirectory SignalGraph.dll))
. "$PSScriptRoot/../../Src/PowerShell.CSharp/Bootstrap/STNativeSignalCompatibility.ps1"
$cases=[Collections.Generic.List[object]]::new()
function Check($Id,$Condition){$cases.Add([ordered]@{Id=$Id;Pass=[bool]$Condition})}
$signal=[SignalGraph.Signal]::Start('ABI',$null)|Select-Object -Last 1
Check 'selected-native-underlying-type' ($signal.GetType() -eq [SignalGraph.Signal])
$payload=[pscustomobject]@{Data='Test'}
$added=Add-PathToDictionary $signal '@.Base' $payload
$resolved=Resolve-PathFromDictionary $signal '@.Base'
Check 'native-result-write-after-select' (-not $added.Failure() -and $signal.HasResult())
Check 'dynamic-member-reference-preserved' ([object]::ReferenceEquals($resolved.Result,$payload))
Check 'dynamic-member-value' ((Resolve-PathFromDictionary $signal '@.Base.Data').Result -ceq 'Test')
$id=[guid]::NewGuid().ToString()
# Exact existing PS plan calling conventions: Append does not concatenate a symbolic Result.
$added=Add-PathToDictionary $signal '*.#.TestRunId.@' $id -AddStyle Append
Check 'symbolic-append-write' (-not $added.Failure() -and (Resolve-PathFromDictionary $signal '*.#.TestRunId.@').Result -ceq $id)
$added=Add-PathToDictionary $signal '*.#.Adapters.*'
Check 'omitted-value-pointer-creation' (-not $added.Failure() -and (Resolve-PathFromDictionary $signal '*.#.Adapters.*').Result -is [SignalGraph.Graph])
$registered=[SignalGraph.Signal]::Start('Registered',$null)
$added=Add-PathToDictionary $signal '*.#.Adapters.*.Selected' $registered
Check 'implicit-grid-registration-reference' (-not $added.Failure() -and [object]::ReferenceEquals((Resolve-PathFromDictionary $signal '*.#.Adapters.*.#.Selected').Result,$registered))
$step=[pscustomobject]@{Name='Selected'};$original=$step
$added=Add-PathToDictionary $step VirtualPath 'local.json'
Check 'ps-note-property-write-preserves-object' (-not $added.Failure() -and [object]::ReferenceEquals($step,$original) -and $step.VirtualPath -ceq 'local.json')
$newValue=[pscustomobject]@{Value='same-reference'}
$added=Add-PathToDictionary $step Missing $newValue -AddStyle Append
Check 'missing-ps-property-append-assigns-reference' (-not $added.Failure() -and [object]::ReferenceEquals($step.Missing,$newValue))
Check 'array-name-selector' ([object]::ReferenceEquals((Resolve-PathFromDictionary @{Steps=@($step)} 'Steps.Selected').Result,$step))
Check 'false-result-retained' ((Resolve-PathFromDictionary @{Flag=$false} Flag).Result -is [bool] -and (Resolve-PathFromDictionary @{Flag=$false} Flag).Result -eq $false)
$failed=[SignalGraph.Signal]::Start('Failure',$null)
$logged=$failed.LogCritical('expected',$null,$null)
Check 'logging-returns-operation-signal' ([object]::ReferenceEquals($failed,$logged) -and $failed.Failure())
Check 'missing-path-remains-failure' ((Resolve-PathFromDictionary @{Data='Test'} Missing).Failure())
$report=[ordered]@{PassCount=@($cases|Where-Object Pass).Count;FailCount=@($cases|Where-Object {-not $_.Pass}).Count;SkipCount=0;Total=$cases.Count;Cases=@($cases);SignalAssembly=[SignalGraph.Signal].Assembly.Location;SignalAssemblySha256=(Get-FileHash ([SignalGraph.Signal].Assembly.Location)).Hash;CompatibilitySha256=(Get-FileHash "$PSScriptRoot/../../Src/PowerShell.CSharp/Bootstrap/STNativeSignalCompatibility.ps1").Hash}
$report|ConvertTo-Json -Depth 8|Set-Content $Receipt -Encoding utf8NoBOM
"$($report.PassCount)/$($report.FailCount)/$($report.Total), skip0"
if($report.FailCount){$cases|Where-Object {-not $_.Pass}|ForEach-Object Id;exit 1}
