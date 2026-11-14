[CmdletBinding()]
param([string]$SelectionPacket,[string]$SelectionPacketSha256,
      [ValidateSet('IdentityOnly','LoaderCheck','SemanticCheck')][string]$Mode='IdentityOnly',
      [string]$EntryPoint,[Parameter(Mandatory)][string]$RunRoot)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../../Src/PowerShell/Bootstrap/STFoundationSelection.ps1"
try {
    if ([string]::IsNullOrWhiteSpace($SelectionPacket) -or [string]::IsNullOrWhiteSpace($SelectionPacketSha256)) {
        throw 'ST_SELECTION_REQUIRED: explicit reviewed packet and digest are required.'
    }
    $selection=Read-STSelectionPacket -Path $SelectionPacket -Sha256 $SelectionPacketSha256
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
    $child=@'
param($Helper,$Packet,$Sha,$Receipt,$EntryPoint,$SemanticScript)
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
    if ($SemanticScript) { $semantic=& $SemanticScript -RunRoot (Split-Path $Receipt) -Selection $resolved }
    $result=[ordered]@{Mode='LoaderCheck';Pass=$true;Root=$root;Worker=$workerOrigin;WorkerDisposed=$true;EntryPoint=$EntryPoint;PowerShell=$PSVersionTable.PSVersion.ToString();Runtime=[Environment]::Version.ToString();OS=[Runtime.InteropServices.RuntimeInformation]::OSDescription;Architecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()}
    if ($SemanticScript) { $result.Mode='SemanticCheck';$result.Semantic=$semantic }
    [IO.File]::WriteAllText($Receipt,($result|ConvertTo-Json -Depth 12))
    exit 0
} catch { [Console]::Error.WriteLine($_.Exception.Message);exit 1 }
'@
    [IO.File]::WriteAllText($bootstrap,$child)
    $start=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'))
    if (-not $IsWindows) { $start.FileName=Join-Path $PSHOME 'pwsh' }
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $semanticScript=if($Mode -eq 'SemanticCheck'){Resolve-STSelectionPath "$PSScriptRoot/Wave1.Semantics.ps1"}else{''}
    foreach ($arg in @('-NoLogo','-NoProfile','-File',$bootstrap,$helper,$selection.PacketPath,$selection.PacketSha256,(Join-Path $RunRoot 'receipt.json'),[string]$EntryPoint,$semanticScript)) { $start.ArgumentList.Add($arg) }
    $start.Environment['ST_FOUNDATION_MANIFEST']=$selection.Foundation.Manifest
    $start.Environment['ST_FOUNDATION_SELECTION_PACKET']=$selection.PacketPath
    $start.Environment['ST_FOUNDATION_SELECTION_SHA256']=$selection.PacketSha256
    $start.Environment['PSModulePath']=(Split-Path $selection.SignalGraph.Root)+[IO.Path]::PathSeparator+(Join-Path $PSHOME 'Modules')
    $process=[Diagnostics.Process]::Start($start)
    try {
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) { $process.Kill($true);throw 'ST_CHILD_TIMEOUT: child exceeded two minutes.' }
        [IO.File]::WriteAllText((Join-Path $RunRoot 'stdout.txt'),$stdout.GetAwaiter().GetResult())
        $errorText=$stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $RunRoot 'stderr.txt'),$errorText)
        if ($process.ExitCode -ne 0) { throw "ST_CHILD_FAILED: $errorText" }
    } finally { $process.Dispose() }
    Get-Content -LiteralPath (Join-Path $RunRoot 'receipt.json') -Raw
} catch { [Console]::Error.WriteLine($_.Exception.Message);exit 1 }
