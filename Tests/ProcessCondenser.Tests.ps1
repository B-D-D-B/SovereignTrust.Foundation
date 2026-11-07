using module SignalGraph
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Src/PowerShell/SovereignTrust.Foundation.psd1') -Force
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message }; $script:assertions++ }
$script:assertions = 0
$bootstrap = [Signal]::Start('ProcessCondenser.Bootstrap') | Select-Object -Last 1
$bootstrap.SetResult([pscustomobject]@{})
$started = New-Conductor -HostConductor $null -ConductionSignal $bootstrap | Select-Object -Last 1
Assert-True (-not $started.Failure() -and $started.HasResult()) 'Conductor failed to initialize.'
$conductor = $started.GetResult()
$control = [Signal]::Start('Control') | Select-Object -Last 1
$null = $control.SetJacket($conductor.Signal)
$null = $control.SetPointer($conductor.Signal.GetPointer())
$run = [Signal]::Start('Run') | Select-Object -Last 1
$run.SetControl($control)
$null = $run.SetJacket($control)
$null = $run.SetPointer($conductor.Signal.GetPointer())
$child = (Resolve-Path (Join-Path $PSScriptRoot 'Fixtures/ProcessChild.ps1')).ProviderPath
$exe = (Get-Command pwsh -CommandType Application).Source
function Invoke-Case([string[]]$Arguments,[int]$Timeout=5000,[int]$OutputCap=1024,[byte[]]$InputBytes=$null,[bool]$SupplyInput=$false) {
    $config = [pscustomobject]@{Executable=$exe;Arguments=([string[]](@('-NoProfile','-File',$child)+$Arguments));TimeoutMilliseconds=$Timeout;MaximumOutputBytes=$OutputCap;MaximumErrorBytes=1024}
    if ($SupplyInput) { $config | Add-Member -NotePropertyName InputBytes -NotePropertyValue $InputBytes }
    Invoke-MappedAdapter -Adapter 'Condenser.Process' -Activity 'Run' -Signal $run -Plan ([pscustomobject]@{Config=$config}) -ItemSignal $run | Select-Object -Last 1
}
$echo = Invoke-Case @('Echo','hello world')
Assert-True (-not $echo.Failure() -and $echo.HasResult()) "Echo route failed: $(@($echo.Entries | ForEach-Object Message) -join ' | ')"
Assert-True ([System.Text.Encoding]::UTF8.GetString($echo.GetResult().StandardOutputBytes) -ceq 'hello world') 'Argument with space changed.'
$binary = Invoke-Case @('Binary')
Assert-True (-not $binary.Failure() -and ([System.Convert]::ToHexString($binary.GetResult().StandardOutputBytes)) -ceq '000100FF') 'Binary output changed.'
$stdin = Invoke-Case @('Stdin') -InputBytes ([byte[]](0,1,255)) -SupplyInput $true
Assert-True (-not $stdin.Failure() -and ([System.Convert]::ToHexString($stdin.GetResult().StandardOutputBytes)) -ceq '0001FF') "Binary stdin changed: $(@($stdin.Entries | ForEach-Object Message) -join ' | ')"
$zero = Invoke-Case @('Stdin') -InputBytes ([byte[]]@()) -SupplyInput $true
Assert-True (-not $zero.Failure() -and $zero.GetResult().StandardOutputBytes.Length -eq 0) 'Zero-byte stdin failed.'
$nonzero = Invoke-Case @('Nonzero')
Assert-True (-not $nonzero.Failure() -and $nonzero.GetResult().ExitCode -eq 7 -and [System.Text.Encoding]::UTF8.GetString($nonzero.GetResult().StandardErrorBytes) -ceq 'diagnostic') 'Nonzero exit contract changed.'
$flood = Invoke-Case @('Flood') -OutputCap 32
Assert-True ($flood.Failure() -and -not $flood.HasResult()) 'Output cap did not fail.'
$errorFlood = Invoke-Case @('ErrorFlood')
Assert-True ($errorFlood.Failure() -and -not $errorFlood.HasResult()) 'Error cap did not fail.'
$timeoutClock = [System.Diagnostics.Stopwatch]::StartNew()
$sleep = Invoke-Case @('Sleep') -Timeout 100
$timeoutClock.Stop()
Assert-True ($sleep.Failure() -and -not $sleep.HasResult()) 'Timeout did not fail.'
Assert-True ($timeoutClock.ElapsedMilliseconds -lt 4500) 'Timeout plus cleanup exceeded 2000+2000 ms waits.'
$blocked = Invoke-Case @('BlockStdin') -Timeout 100 -InputBytes ([byte[]]::new(8388608)) -SupplyInput $true
Assert-True ($blocked.Failure() -and -not $blocked.HasResult()) 'Blocked stdin did not fail.'
$marker = Join-Path ([System.IO.Path]::GetTempPath()) ("process-tree-$([guid]::NewGuid().ToString('N')).pid")
try {
    $treeClock = [System.Diagnostics.Stopwatch]::StartNew()
    $tree = Invoke-Case @('Tree',$marker) -Timeout 1500
    $treeClock.Stop()
    Assert-True ($tree.Failure() -and -not $tree.HasResult()) 'Tree timeout did not fail.'
    Assert-True ($treeClock.ElapsedMilliseconds -lt 6000) 'Tree cleanup exceeded 2000+2000 ms waits.'
    Assert-True (Test-Path $marker) 'Descendant marker absent.'
    $descendantId = [int][System.IO.File]::ReadAllText($marker)
    Start-Sleep -Milliseconds 100
    Assert-True ($null -eq (Get-Process -Id $descendantId -ErrorAction SilentlyContinue)) 'Descendant survived tree termination.'
} finally { if (Test-Path $marker) { Remove-Item -LiteralPath $marker -Force } }
$invalidActivity = Invoke-MappedAdapter -Adapter 'Condenser.Process' -Activity 'run' -Signal $run -Plan ([pscustomobject]@{Config=[pscustomobject]@{}}) -ItemSignal $run | Select-Object -Last 1
Assert-True ($invalidActivity.Failure() -and -not $invalidActivity.HasResult()) 'Invalid activity reached process.'
$invalidConfig = Invoke-MappedAdapter -Adapter 'Condenser.Process' -Activity 'Run' -Signal $run -Plan ([pscustomobject]@{Config=[pscustomobject]@{Executable=$exe;Arguments=@();TimeoutMilliseconds=0;MaximumOutputBytes=1;MaximumErrorBytes=1}}) -ItemSignal $run | Select-Object -Last 1
Assert-True ($invalidConfig.Failure() -and -not $invalidConfig.HasResult()) 'Invalid config reached process.'
$startFailure = Invoke-MappedAdapter -Adapter 'Condenser.Process' -Activity 'Run' -Signal $run -Plan ([pscustomobject]@{Config=[pscustomobject]@{Executable=$child;Arguments=@();TimeoutMilliseconds=1000;MaximumOutputBytes=1;MaximumErrorBytes=1}}) -ItemSignal $run | Select-Object -Last 1
Assert-True ($startFailure.Failure() -and -not $startFailure.HasResult()) 'Start failure returned Result.'
Write-Output "PASS: $script:assertions ProcessCondenser assertions."
