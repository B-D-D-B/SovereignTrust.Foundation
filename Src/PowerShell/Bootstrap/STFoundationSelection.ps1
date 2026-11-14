# This bootstrap deliberately has no using-module statements or product types.
function Resolve-STSelectionPath {
    param([Parameter(Mandatory)][string]$Path, [switch]$Directory)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathFullyQualified($Path)) {
        throw 'ST_SELECTION_PATH: an absolute nonblank path is required.'
    }
    $full = [IO.Path]::GetFullPath($Path)
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if (($item -is [IO.DirectoryInfo]) -ne [bool]$Directory) { throw 'ST_SELECTION_PATH: wrong path kind.' }
    for ($current = $item; $null -ne $current; $current = $current.Parent) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "ST_SELECTION_REDIRECTION: $($current.FullName)"
        }
        if ($current -isnot [IO.DirectoryInfo]) { $current = $current.Directory; if ($null -eq $current) { break } }
    }
    return $item.FullName
}

function Read-STSelectionPacket {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Sha256,
          [string]$KnownSignalAssembly)
    if ($Sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw 'ST_SELECTION_HASH: invalid packet digest.' }
    $canonical = Resolve-STSelectionPath $Path
    if ((Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash -ne $Sha256) {
        throw 'ST_SELECTION_HASH: packet identity mismatch.'
    }
    $selection = Get-Content -LiteralPath $canonical -Raw | ConvertFrom-Json -Depth 30
    if ($selection.Schema -ne 'ST.Foundation.Selection/1') { throw 'ST_SELECTION_SCHEMA: unsupported selection packet.' }
    $selection | Add-Member -NotePropertyName PacketPath -NotePropertyValue $canonical -Force
    $selection | Add-Member -NotePropertyName PacketSha256 -NotePropertyValue $Sha256.ToUpperInvariant() -Force
    if ($KnownSignalAssembly) { $selection | Add-Member -NotePropertyName KnownSignalAssembly -NotePropertyValue $KnownSignalAssembly }
    Assert-STFoundationSelection -Selection $selection
    return $selection
}

function Get-STFoundationSelection {
    param([Parameter(Mandatory)][string]$LegacyManifest, [object]$SelectionPacket,
          [ValidateSet('Absent','Present')][string]$SelectionState)
    $variables = [Environment]::GetEnvironmentVariables('Process')
    $present = $variables.Contains('ST_FOUNDATION_MANIFEST')
    if ($PSBoundParameters.ContainsKey('SelectionState') -and (($SelectionState -eq 'Present') -ne $present)) {
        throw 'ST_SELECTION_STATE: explicit state disagrees with process environment.'
    }
    $manifest = if ($present) { [string]$variables['ST_FOUNDATION_MANIFEST'] } else { $LegacyManifest }
    if ([string]::IsNullOrWhiteSpace($manifest)) { throw 'ST_SELECTION_BLANK: present blank selection is invalid.' }
    $manifest = Resolve-STSelectionPath $manifest
    if ([IO.Path]::GetFileName($manifest) -ne 'SovereignTrust.Foundation.psd1') {
        throw 'ST_SELECTION_MODULE: wrong Foundation manifest name.'
    }
    if ($null -eq $SelectionPacket -and ($variables.Contains('ST_FOUNDATION_SELECTION_PACKET') -or $variables.Contains('ST_FOUNDATION_SELECTION_SHA256'))) {
        if ([string]::IsNullOrWhiteSpace($variables['ST_FOUNDATION_SELECTION_PACKET']) -or [string]::IsNullOrWhiteSpace($variables['ST_FOUNDATION_SELECTION_SHA256'])) {
            throw 'ST_SELECTION_PACKET: partial or blank explicit packet state.'
        }
        $SelectionPacket = Read-STSelectionPacket -Path $variables['ST_FOUNDATION_SELECTION_PACKET'] `
            -Sha256 $variables['ST_FOUNDATION_SELECTION_SHA256']
    }
    if ($null -eq $SelectionPacket -and $present) {
        # Trust the reviewed deployment configuration beside this bootstrap's
        # repository, never an arbitrary file discovered inside selected code.
        $codeDirectory=Split-Path -Parent $MyInvocation.MyCommand.ScriptBlock.File
        $trustedRoot=[IO.Path]::GetFullPath((Join-Path $codeDirectory '../../..'))
        $descriptorPath=Join-Path $trustedRoot 'STFoundation.DefaultSelection.json'
        if (-not (Test-Path -LiteralPath $descriptorPath -PathType Leaf)) { throw 'ST_SELECTION_DEFAULT: trusted default descriptor is missing.' }
        $descriptorPath=Resolve-STSelectionPath $descriptorPath
        $descriptor=Get-Content -LiteralPath $descriptorPath -Raw|ConvertFrom-Json -Depth 10
        if ($descriptor.Schema -ne 'ST.Foundation.DefaultSelection/1' -or $descriptor.FoundationManifest -ne $manifest) {
            throw 'ST_SELECTION_DEFAULT: selected manifest is not the approved normal default.'
        }
        $SelectionPacket=Read-STSelectionPacket -Path $descriptor.PacketPath -Sha256 $descriptor.PacketSha256
        $SelectionPacket|Add-Member -NotePropertyName DefaultDescriptor -NotePropertyValue $descriptorPath
    }
    if ($null -ne $SelectionPacket) {
        Assert-STFoundationSelection $SelectionPacket
        if ($manifest -ne $SelectionPacket.Foundation.Manifest) { throw 'ST_SELECTION_MISMATCH: manifest differs from reviewed packet.' }
        return $SelectionPacket
    }
    if ($present) { throw 'ST_SELECTION_PACKET: explicit selection requires a reviewed packet.' }
    # Legacy callers retain their existing discovery contract. This observation is
    # deliberately not represented as a reviewed full-tree selection packet.
    [pscustomobject]@{ Schema='ST.Foundation.Legacy/1'; Foundation=[pscustomobject]@{Manifest=$manifest} }
}

function Assert-STFoundationSelection {
    param([Parameter(Mandatory)][object]$Selection, [switch]$RequireLoaded)
    if ($Selection.Schema -eq 'ST.Foundation.Legacy/1') {
        $null = Resolve-STSelectionPath $Selection.Foundation.Manifest
        return
    }
    foreach ($name in @('Foundation','SignalGraph')) {
        $module = $Selection.$name
        $root = Resolve-STSelectionPath -Path $module.Root -Directory
        $manifest = Resolve-STSelectionPath $module.Manifest
        $expectedName = if ($name -eq 'Foundation') { 'SovereignTrust.Foundation' } else { 'SignalGraph' }
        if ([IO.Path]::GetFileName($manifest) -ne "$expectedName.psd1" -or
            [IO.Path]::GetDirectoryName($manifest) -ne $root) { throw 'ST_SELECTION_MODULE: root/manifest mismatch.' }
        $data = Import-PowerShellDataFile -LiteralPath $manifest -ErrorAction Stop
        if ([string]$data.GUID -ne [string]$module.Guid -or [string]$data.ModuleVersion -ne [string]$module.Version -or
            [string]$data.RootModule -ne "$expectedName.psm1") { throw 'ST_SELECTION_MODULE: manifest identity mismatch.' }
        $files = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction Stop)
        $directories = @(Get-ChildItem -LiteralPath $root -Directory -Recurse -Force -ErrorAction Stop)
        if ($files.Count -ne @($module.Files).Count -or $directories.Count -ne @($module.Directories).Count) {
            throw 'ST_SELECTION_MEMBERSHIP: selected tree membership changed.'
        }
        $expected = @{}
        foreach ($file in @($module.Files)) {
            if ($file.Path -match '(^|/)\.\.(/|$)' -or [IO.Path]::IsPathFullyQualified($file.Path) -or $expected.ContainsKey($file.Path)) {
                throw 'ST_SELECTION_MEMBERSHIP: invalid packet member.'
            }
            $expected[$file.Path] = $file
        }
        foreach ($file in $files) {
            $null = Resolve-STSelectionPath $file.FullName
            $relative = [IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/')
            $entry = $expected[$relative]
            if ($null -eq $entry -or $entry.Sha256 -notmatch '^[0-9A-Fa-f]{64}$' -or
                $file.Length -ne $entry.Length -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne $entry.Sha256) {
                throw "ST_SELECTION_HASH: selected member drift: $relative"
            }
        }
        foreach ($directory in $directories) {
            $null = Resolve-STSelectionPath -Path $directory.FullName -Directory
            if ([IO.Path]::GetRelativePath($root,$directory.FullName).Replace('\','/') -notin @($module.Directories)) {
                throw 'ST_SELECTION_MEMBERSHIP: directory mismatch.'
            }
        }
        $loaded = @(Get-Module -All -Name $expectedName)
        if ($loaded.Count -gt 1) { throw "ST_SELECTION_DUPLICATE: $expectedName requires a fresh process." }
        if ($RequireLoaded -and $loaded.Count -ne 1) { throw "ST_SELECTION_LOADED: $expectedName is not loaded." }
        foreach ($actual in $loaded) {
            if ($actual.ModuleBase -ne $root -or $actual.Path -ne (Join-Path $root "$expectedName.psm1") -or
                [string]$actual.Guid -ne [string]$module.Guid -or [string]$actual.Version -ne [string]$module.Version) {
                throw "ST_SELECTION_LOADED: wrong $expectedName origin; start a fresh process."
            }
        }
    }
    $knownAssembly = if (Get-Module SignalGraph) { & (Get-Module SignalGraph) { [Signal].Assembly.FullName } } else {
        $knownProperty=$Selection.PSObject.Properties['KnownSignalAssembly']
        if ($null -ne $knownProperty) { $knownProperty.Value } else { $null }
    }
    foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
        if ($null -ne $assembly.GetType('Signal',$false) -or $null -ne $assembly.GetType('SignalGraph.Signal',$false)) {
            if (-not $knownAssembly -or $assembly.FullName -ne $knownAssembly) {
                throw 'ST_SELECTION_TYPE: unknown preloaded Signal type requires a fresh process.'
            }
        }
    }
}

function Get-STSelectedDiscoveryPath {
    param([Parameter(Mandatory)][object]$Selection)
    $roots=@((Split-Path -Parent $Selection.SignalGraph.Root),(Join-Path $PSHOME 'Modules'))
    if ($IsWindows) {
        $roots+=Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'PowerShell/Modules'
        $roots+=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell/Modules'
    }
    return $roots -join [IO.Path]::PathSeparator
}

function Initialize-STSelectedProcessDiscovery {
    param([Parameter(Mandatory)][object]$Selection)
    if ($Selection.Schema -eq 'ST.Foundation.Legacy/1') { return }
    Assert-STFoundationSelection $Selection
    $worker=Get-Variable -Name STSelectedWorkerContext -Scope Global -ErrorAction SilentlyContinue
    $prepared=Get-Variable -Name STSelectedDiscoveryPrepared -Scope Global -ErrorAction SilentlyContinue
    if (($null -ne $worker -and [bool]$worker.Value) -or
        ($null -ne $prepared -and [bool]$prepared.Value) -or
        @(Get-Module -All SovereignTrust.Foundation).Count -gt 0) {
        Assert-STSelectedDiscovery $Selection
        return
    }
    # A parent may have explicitly loaded the exact selected SG first. The
    # identity/type assertion above rejects every other preload before writing.
    $expected=Get-STSelectedDiscoveryPath $Selection
    if ($env:PSModulePath -cne $expected) { $env:PSModulePath=$expected }
    Initialize-STSelectedDependency $Selection
    $global:STSelectedDiscoveryPrepared=$true
}

function Assert-STSelectedDiscovery {
    param([Parameter(Mandatory)][object]$Selection)
    if ($env:PSModulePath -cne (Get-STSelectedDiscoveryPath $Selection)) {
        throw 'ST_SELECTION_DISCOVERY: unexpected process discovery path; workers cannot repair it.'
    }
    $available=@(Get-Module -ListAvailable -Name SignalGraph)
    if ($available.Count -eq 0 -or $available[0].Path -ne $Selection.SignalGraph.Manifest -or $available[0].ModuleBase -ne $Selection.SignalGraph.Root) {
        throw 'ST_SELECTION_DISCOVERY: by-name discovery does not select the reviewed first module.'
    }
}

function Initialize-STSelectedDependency {
    param([Parameter(Mandatory)][object]$Selection)
    if ($Selection.Schema -eq 'ST.Foundation.Legacy/1') { return }
    Assert-STFoundationSelection $Selection
    $global:PSModuleAutoLoadingPreference = 'None'
    Assert-STSelectedDiscovery $Selection
    if (-not (Get-Module SignalGraph)) { Import-Module -Name $Selection.SignalGraph.Manifest -ErrorAction Stop }
    Assert-STFoundationSelection $Selection
    $before=@(Get-Module -All SignalGraph|ForEach-Object Path)
    $expectedType=& (Get-Module SignalGraph) { [Signal] }
    $namedType=& ([scriptblock]::Create('using module SignalGraph; [Signal]'))
    $after=@(Get-Module -All SignalGraph|ForEach-Object Path)
    if (-not [object]::ReferenceEquals($expectedType,$namedType) -or ($before -join '|') -cne ($after -join '|')) {
        throw 'ST_SELECTION_DISCOVERY: by-name type/module origin differs from the reviewed dependency.'
    }
}

function Assert-STSelectedEntryPoint {
    param([Parameter(Mandatory)][object]$Selection,[Parameter(Mandatory)][string]$EntryPoint)
    $canonical=Resolve-STSelectionPath $EntryPoint
    $matches=@($Selection.EntryPoints|Where-Object {$_.Manifest -eq $canonical})
    if ($matches.Count -ne 1) { throw 'ST_ENTRYPOINT_MEMBERSHIP: entry is not in the reviewed selection packet.' }
    $entry=$matches[0]
    $root=Resolve-STSelectionPath -Path $entry.Root -Directory
    if ((Split-Path $canonical) -ne $root) { throw 'ST_ENTRYPOINT_IDENTITY: root mismatch.' }
    $files=@(Get-ChildItem -LiteralPath $root -File -Recurse -Force)
    $directories=@(Get-ChildItem -LiteralPath $root -Directory -Recurse -Force)
    if ($files.Count -ne @($entry.Files).Count -or $directories.Count -ne @($entry.Directories).Count) { throw 'ST_ENTRYPOINT_IDENTITY: membership drift.' }
    foreach ($file in $files) {
        $null=Resolve-STSelectionPath $file.FullName
        $relative=[IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/')
        $expected=@($entry.Files|Where-Object Path -eq $relative)
        if ($expected.Count -ne 1 -or $file.Length -ne $expected[0].Length -or
            $expected[0].Sha256 -notmatch '^[0-9A-Fa-f]{64}$' -or (Get-FileHash -LiteralPath $file.FullName).Hash -ne $expected[0].Sha256) {
            throw 'ST_ENTRYPOINT_IDENTITY: reviewed adapter file drift.'
        }
    }
    foreach ($directory in $directories) {
        $null=Resolve-STSelectionPath -Path $directory.FullName -Directory
        if ([IO.Path]::GetRelativePath($root,$directory.FullName).Replace('\','/') -notin @($entry.Directories)) { throw 'ST_ENTRYPOINT_IDENTITY: directory drift.' }
    }
    $guard=Resolve-STSelectionPath $entry.Guard.Path
    if ($entry.Guard.Sha256 -notmatch '^[0-9A-Fa-f]{64}$' -or (Get-FileHash -LiteralPath $guard).Hash -ne $entry.Guard.Sha256) { throw 'ST_ENTRYPOINT_IDENTITY: preparse bootstrap drift.' }
    $data=Import-PowerShellDataFile -LiteralPath $canonical
    if (@($data.ScriptsToProcess).Count -ne 1 -or $data.ScriptsToProcess[0] -ne '../../../Bootstrap/Initialize-STFoundation.ps1' -or
        [IO.Path]::GetFullPath((Join-Path $root $data.ScriptsToProcess[0])) -ne $guard -or
        $data.RootModule -ne ([IO.Path]::GetFileNameWithoutExtension($canonical)+'.psm1')) {
        throw 'ST_ENTRYPOINT_IDENTITY: unreviewed initialization script/root.'
    }
}

function Import-STSelectedFoundation {
    param([Parameter(Mandatory)][object]$Selection)
    if ($Selection.Schema -eq 'ST.Foundation.Legacy/1') {
        $loaded = @(Get-Module -All SovereignTrust.Foundation)
        if ($loaded.Count -gt 1 -or ($loaded.Count -eq 1 -and $loaded[0].ModuleBase -ne (Split-Path $Selection.Foundation.Manifest))) {
            throw 'ST_SELECTION_LOADED: legacy Foundation origin mismatch; start a fresh process.'
        }
        if ($loaded.Count -eq 0) { Import-Module $Selection.Foundation.Manifest -Global -ErrorAction Stop }
        return
    }
    Initialize-STSelectedDependency $Selection
    Assert-STFoundationSelection $Selection
    if (-not (Get-Module SovereignTrust.Foundation)) {
        Import-Module -Name $Selection.Foundation.Manifest -Global -ErrorAction Stop
    }
    Assert-STFoundationSelection -Selection $Selection -RequireLoaded
    Initialize-STSelectedAdapterTypes -Selection $Selection
}

function Initialize-STSelectedAdapterTypes {
    param([Parameter(Mandatory)][object]$Selection)
    # Exactly two existing adapters consume runtime dot-sourced Foundation
    # classes in their parsers. Preflight all types before adding any alias.
    $foundation=Get-Module SovereignTrust.Foundation
    if ($foundation.ModuleBase -ne $Selection.Foundation.Root) { throw 'ST_SELECTION_TYPE_ALIAS: wrong Foundation origin.' }
    $api=[psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators',$false)
    if ($null -eq $api) { throw 'ST_SELECTION_TYPE_ALIAS: this PowerShell host lacks the required API.' }
    $types=[ordered]@{
        MappedTokenAdapter={ [MappedTokenAdapter] }
        MappedSessionAdapter={ [MappedSessionAdapter] }
    }
    $verified=[ordered]@{}
    foreach ($name in $types.Keys) {
        $expected=& $foundation $types[$name]
        $again=& $foundation $types[$name]
        if ($expected -isnot [type] -or $expected.FullName -ne $name -or -not [object]::ReferenceEquals($expected,$again)) {
            throw "ST_SELECTION_TYPE_ALIAS: selected private Type $name is unavailable."
        }
        if ($api::Get.ContainsKey($name) -and -not [object]::ReferenceEquals($api::Get[$name],$expected)) {
            throw "ST_SELECTION_TYPE_ALIAS: existing $name collision; use a fresh process."
        }
        $verified[$name]=$expected
    }
    foreach ($name in $verified.Keys) {
        if (-not $api::Get.ContainsKey($name)) { $api::Add($name,$verified[$name]) }
        if (-not [object]::ReferenceEquals($api::Get[$name],$verified[$name])) {
            throw 'ST_SELECTION_TYPE_ALIAS: registration verification failed; stop this process.'
        }
    }
}

function Get-STSelectionProvenance {
    param([Parameter(Mandatory)][object]$Selection)
    Assert-STFoundationSelection -Selection $Selection -RequireLoaded
    $sg = Get-Module SignalGraph
    $type = & $sg { [Signal] }
    $signal = & $sg { [Signal]::Start('SelectionLocalAssertion') }
    if ($null -eq $signal -or $signal.Name -ne 'SelectionLocalAssertion' -or $signal.Failure()) {
        throw 'ST_SELECTION_ASSERTION: local Signal assertion failed.'
    }
    [pscustomobject]@{
        ProcessId=$PID; FoundationPath=(Get-Module SovereignTrust.Foundation).Path
        SignalGraphPath=$sg.Path; SignalType=$type.AssemblyQualifiedName
        SignalModule=$type.Module.Name; SignalSource=$Selection.SignalGraph.Manifest
        PacketSha256=$Selection.PacketSha256
    }
}

function New-STSelectedRunspace {
    param([Parameter(Mandatory)][object]$Selection)
    Assert-STSelectedDiscovery $Selection
    Assert-STFoundationSelection $Selection
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $ps = [powershell]::Create()
    try {
        $ps.Runspace=$runspace
        $bootstrap=Join-Path $PSScriptRoot 'STFoundationSelection.ps1'
        $knownAssembly = & (Get-Module SignalGraph) { [Signal].Assembly.FullName }
        $expectedDiscovery=Get-STSelectedDiscoveryPath $Selection
        $null=$ps.AddScript({param($bootstrap,$packet,$sha,$knownAssembly,$expectedDiscovery)
            $global:STSelectedWorkerContext=$true
            if ($env:PSModulePath -cne $expectedDiscovery) { throw 'ST_SELECTION_DISCOVERY: worker discovery drift before bootstrap.' }
            . $bootstrap
            $selection=Read-STSelectionPacket -Path $packet -Sha256 $sha -KnownSignalAssembly $knownAssembly
            Import-STSelectedFoundation $selection
            Get-STSelectionProvenance $selection
        }.ToString()).AddArgument($bootstrap).AddArgument($Selection.PacketPath).AddArgument($Selection.PacketSha256).AddArgument($knownAssembly).AddArgument($expectedDiscovery)
        $result=@($ps.Invoke())
        if ($ps.HadErrors -or $result.Count -ne 1) { throw "ST_SELECTION_WORKER: $($ps.Streams.Error | Out-String)" }
        $runspace | Add-Member -NotePropertyName STSelectionProvenance -NotePropertyValue $result[0]
        return $runspace
    } catch { $runspace.Dispose(); throw } finally { $ps.Dispose() }
}

function Get-STWorkerSelection {
    param([string]$FoundationModulePath)
    if (-not [Environment]::GetEnvironmentVariables('Process').Contains('ST_FOUNDATION_MANIFEST')) { return $null }
    $selection=Get-STFoundationSelection -LegacyManifest (Join-Path $PSScriptRoot '../SovereignTrust.Foundation.psd1')
    if ($FoundationModulePath -and (Resolve-STSelectionPath $FoundationModulePath) -ne $selection.Foundation.Manifest) {
        throw 'ST_SELECTION_WORKER_MISMATCH: explicit worker module differs from selected Foundation.'
    }
    Assert-STFoundationSelection -Selection $selection -RequireLoaded
    return $selection
}

function New-STSelectedInitialSessionState {
    param([Parameter(Mandatory)][object]$Selection)
    Assert-STSelectedDiscovery $Selection
    Assert-STFoundationSelection -Selection $Selection -RequireLoaded
    $state=[Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $knownAssembly=& (Get-Module SignalGraph) { [Signal].Assembly.FullName }
    foreach ($entry in @(
        @('STWorkerPacket',$Selection.PacketPath),@('STWorkerSha',$Selection.PacketSha256),
        @('STWorkerKnownAssembly',$knownAssembly),
        @('STWorkerExpectedDiscovery',(Get-STSelectedDiscoveryPath $Selection)))) {
        $state.Variables.Add([Management.Automation.Runspaces.SessionStateVariableEntry]::new($entry[0],$entry[1],'Verified Foundation worker selection'))
    }
    $null=$state.StartupScripts.Add((Join-Path $PSScriptRoot 'STFoundationWorker.ps1'))
    return $state
}
