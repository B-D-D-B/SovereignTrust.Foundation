[CmdletBinding()]
param([string]$SelectionPacket,[string]$SelectionPacketSha256,
      [ValidateSet('IdentityOnly','LoaderCheck','SemanticCheck','C01','StageACheck','CurrentMigration','CurrentMigrationRuntime','NativeAdapters')][string]$Mode='IdentityOnly',
      [string]$EntryPoint,[string]$Cycle,[switch]$ExecuteReviewedRuntime,[Parameter(Mandatory)][string]$RunRoot)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../../Src/PowerShell/Bootstrap/STFoundationSelection.ps1"
try {
    if ([string]::IsNullOrWhiteSpace($SelectionPacket) -or [string]::IsNullOrWhiteSpace($SelectionPacketSha256)) {
        throw 'ST_SELECTION_REQUIRED: explicit reviewed packet and digest are required.'
    }
    if((Get-FileHash -LiteralPath $SelectionPacket).Hash -ne $SelectionPacketSha256){throw 'ST_SELECTION_HASH: packet mismatch'}
    $native=(Get-Content $SelectionPacket -Raw|ConvertFrom-Json).Schema -ceq 'ST.Foundation.NativeSelection/2'
    if($native){. "$PSScriptRoot/../../Src/PowerShell.CSharp/Bootstrap/STFoundationSelection.ps1"}
    $selection=Read-STSelectionPacket -Path $SelectionPacket -Sha256 $SelectionPacketSha256
    if($Mode -in 'C01','StageACheck','CurrentMigration','CurrentMigrationRuntime'){
        if(-not $ExecuteReviewedRuntime -or [string]::IsNullOrWhiteSpace($Cycle)){throw 'C01_OPT_IN: explicit cycle/runtime opt-in required'}
        $Cycle=Resolve-STSelectionPath -Path $Cycle -Directory
    }
    if (-not [IO.Path]::IsPathFullyQualified($RunRoot) -or (Test-Path -LiteralPath $RunRoot)) {
        throw 'ST_RUN_ROOT: a new absolute run directory is required.'
    }
    $parent=Resolve-STSelectionPath -Path (Split-Path $RunRoot) -Directory
    if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($RunRoot)) -ne $parent) { throw 'ST_RUN_ROOT: parent mismatch.' }
    $null=[IO.Directory]::CreateDirectory($RunRoot)
    if ($Mode -eq 'IdentityOnly') {
        $receipt=[ordered]@{Mode=$Mode;ProcessId=$PID;PacketSha256=$selection.PacketSha256;Foundation=$selection.Foundation.Manifest;SignalGraph=$selection.SignalGraph.Manifest;ProductModules=@(Get-Module SovereignTrust.Foundation,SignalGraph).Count;Pass=$true}
        if ($receipt.ProductModules -ne 0) { throw 'ST_IDENTITY_IMPORT: identity-only process is contaminated.' }
        [IO.File]::WriteAllText((Join-Path $RunRoot 'receipt.json'),($receipt|ConvertTo-Json -Depth 10))
        $receipt|ConvertTo-Json -Compress
        exit 0
    }
    if ($EntryPoint) {
        $EntryPoint=Resolve-STSelectionPath $EntryPoint
        if ([IO.Path]::GetExtension($EntryPoint) -ne '.psd1') { throw 'ST_ENTRYPOINT: only guarded adapter manifests are supported.' }
        Assert-STSelectedEntryPoint -Selection $selection -EntryPoint $EntryPoint
    }
    $bootstrap=Join-Path $RunRoot 'child.ps1'
    $helper=Resolve-STSelectionPath "$PSScriptRoot/../../Src/PowerShell/Bootstrap/STFoundationSelection.ps1"
    if($native){$helper=Resolve-STSelectionPath "$PSScriptRoot/../../Src/PowerShell.CSharp/Bootstrap/STFoundationSelection.ps1"}
    $child=@'
param($Helper,$Packet,$Sha,$Receipt,$EntryPoint,$SemanticScript,$Cycle)
$ErrorActionPreference='Stop'
try {
    . $Helper
    $selection=Read-STSelectionPacket -Path $Packet -Sha256 $Sha
    if ($EntryPoint) { Assert-STSelectedEntryPoint -Selection $selection -EntryPoint $EntryPoint }
    # PowerShell can expand discovery paths on process startup. Establish the
    # reviewed value once here, before product imports or worker creation.
    $env:PSModulePath=Get-STSelectedDiscoveryPath $selection
    $resolved=Get-STFoundationSelection -LegacyManifest $selection.Foundation.Manifest -SelectionPacket $selection -SelectionState Present
    Import-STSelectedFoundation $resolved
    $root=Get-STSelectionProvenance $resolved
    $worker=New-STSelectedRunspace $resolved
    try { $workerOrigin=$worker.STSelectionProvenance } finally { $worker.Close();$worker.Dispose() }
    if ($workerOrigin.FoundationPath -ne $root.FoundationPath -or $workerOrigin.SignalGraphPath -ne $root.SignalGraphPath) {throw 'ST_WORKER_CROSSLOAD: root/worker differ.'}
    if ($SemanticScript) {
        [ordered]@{Root=$root;Worker=$workerOrigin;WorkerDisposed=$true;PowerShell=$PSVersionTable.PSVersion.ToString();Runtime=[Environment]::Version.ToString()}|ConvertTo-Json -Depth 12|Set-Content (Join-Path (Split-Path $Receipt) 'loader-provenance.json') -Encoding utf8NoBOM
    }
    if ($EntryPoint) { Assert-STSelectedEntryPoint -Selection $resolved -EntryPoint $EntryPoint; Import-Module -Name $EntryPoint -ErrorAction Stop; Assert-STFoundationSelection -Selection $resolved -RequireLoaded }
    $semantic=$null
    if ($SemanticScript) {
        if($Cycle){$semantic=& $SemanticScript -RunRoot (Split-Path $Receipt) -Selection $resolved -Cycle $Cycle}
        else{$semantic=& $SemanticScript -RunRoot (Split-Path $Receipt) -Selection $resolved}
    }
    $result=[ordered]@{Mode='LoaderCheck';Pass=$true;Root=$root;Worker=$workerOrigin;WorkerDisposed=$true;EntryPoint=$EntryPoint;PowerShell=$PSVersionTable.PSVersion.ToString();Runtime=[Environment]::Version.ToString();OS=[Runtime.InteropServices.RuntimeInformation]::OSDescription;Architecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()}
    if ($SemanticScript) { if($Cycle){$result.Mode=switch([IO.Path]::GetFileName($SemanticScript)){'Wave2.StageA.ps1'{'StageACheck'} 'CurrentMigration.Focused.ps1'{'CurrentMigration'} 'CurrentMigration.Runtime.ps1'{'CurrentMigrationRuntime'} default{'C01'}};$result.Integration=$semantic}else{$result.Mode='SemanticCheck';$result.Semantic=$semantic} }
    [IO.File]::WriteAllText($Receipt,($result|ConvertTo-Json -Depth 12))
    exit 0
} catch { [Console]::Error.WriteLine($_.Exception.Message);exit 1 }
'@
    [IO.File]::WriteAllText($bootstrap,$child)
    $start=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'))
    if (-not $IsWindows) { $start.FileName=Join-Path $PSHOME 'pwsh' }
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $semanticScript=if($Mode -eq 'SemanticCheck'){Resolve-STSelectionPath "$PSScriptRoot/Wave1.Semantics.ps1"}elseif($Mode -eq 'C01'){Resolve-STSelectionPath "$PSScriptRoot/Wave2.C01.ps1"}elseif($Mode -eq 'StageACheck'){Resolve-STSelectionPath "$PSScriptRoot/Wave2.StageA.ps1"}elseif($Mode -eq 'CurrentMigration'){Resolve-STSelectionPath "$PSScriptRoot/CurrentMigration.Focused.ps1"}elseif($Mode -eq 'CurrentMigrationRuntime'){Resolve-STSelectionPath "$PSScriptRoot/CurrentMigration.Runtime.ps1"}elseif($Mode -eq 'NativeAdapters'){Resolve-STSelectionPath "$PSScriptRoot/NativeAdapters.ps1"}else{''}
    foreach ($arg in @('-NoLogo','-NoProfile','-File',$bootstrap,$helper,$selection.PacketPath,$selection.PacketSha256,(Join-Path $RunRoot 'receipt.json'),[string]$EntryPoint,$semanticScript,[string]$Cycle)) { $start.ArgumentList.Add($arg) }
    $start.Environment['ST_FOUNDATION_MANIFEST']=$selection.Foundation.Manifest
    $start.Environment['ST_FOUNDATION_SELECTION_PACKET']=$selection.PacketPath
    $start.Environment['ST_FOUNDATION_SELECTION_SHA256']=$selection.PacketSha256
    $start.Environment['PSModulePath']=if($native){Get-STSelectedDiscoveryPath $selection}else{(Split-Path $selection.SignalGraph.Root)+[IO.Path]::PathSeparator+(Join-Path $PSHOME 'Modules')}
    $process=[Diagnostics.Process]::Start($start)
    $childIdentity=[ordered]@{ProcessId=$process.Id;StartTimeUtc=$process.StartTime.ToUniversalTime().ToString('o');Executable=$start.FileName;Arguments=@($start.ArgumentList);OwnedRunRoot=$RunRoot;State='Started'}
    $lifecyclePath=Join-Path $RunRoot 'child-lifecycle.json'
    $childIdentity|ConvertTo-Json -Depth 8|Set-Content $lifecyclePath -Encoding utf8NoBOM
    try {
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        $timedOut=-not $process.WaitForExit(120000)
        if ($timedOut) {
            if($process.Id -ne $childIdentity.ProcessId -or $process.StartTime.ToUniversalTime().ToString('o') -cne $childIdentity.StartTimeUtc){throw 'ST_CHILD_OWNERSHIP: identity changed; termination forbidden'}
            $childIdentity.State='TimeoutIdentityVerifiedBeforeTermination'
            $childIdentity|ConvertTo-Json -Depth 8|Set-Content $lifecyclePath -Encoding utf8NoBOM
            $process.Kill($true);$process.WaitForExit()
        }
        [IO.File]::WriteAllText((Join-Path $RunRoot 'stdout.txt'),$stdout.GetAwaiter().GetResult())
        $errorText=$stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $RunRoot 'stderr.txt'),$errorText)
        $childIdentity.State=if($timedOut){'TimedOutOwnedChildTerminated'}else{'Exited'}
        $childIdentity.ExitCode=$process.ExitCode;$childIdentity.Exited=$process.HasExited
        $childIdentity|ConvertTo-Json -Depth 8|Set-Content $lifecyclePath -Encoding utf8NoBOM
        if($timedOut){throw 'ST_CHILD_TIMEOUT: owned child killed after two minutes; raw streams preserved.'}
        if ($process.ExitCode -ne 0) { throw "ST_CHILD_FAILED: $errorText" }
    } finally { $process.Dispose() }
    Get-Content -LiteralPath (Join-Path $RunRoot 'receipt.json') -Raw
} catch { [Console]::Error.WriteLine($_.Exception.Message);exit 1 }
