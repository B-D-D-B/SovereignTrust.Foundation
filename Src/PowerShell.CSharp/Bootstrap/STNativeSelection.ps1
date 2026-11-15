# Overrides legacy dependency operations for the explicitly selected native backend.
function Read-STSelectionPacket {
    param([string]$Path,[string]$Sha256,[string]$KnownSignalAssembly)
    $path=Resolve-STSelectionPath $Path
    if($Sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash $path).Hash -ne $Sha256){throw 'ST_NATIVE_PACKET: digest mismatch'}
    $selection=Get-Content $path -Raw|ConvertFrom-Json -Depth 40
    $selection|Add-Member PacketPath $path -Force;$selection|Add-Member PacketSha256 $Sha256 -Force
    Assert-STFoundationSelection $selection;$selection
}
function Assert-STFoundationSelection {
    param([Parameter(Mandatory)]$Selection,[switch]$RequireLoaded)
    if($Selection.Schema -cne 'ST.Foundation.NativeSelection/2' -or $Selection.SignalGraph.Backend -cne 'Native'){throw 'ST_NATIVE_PACKET: explicit native backend required'}
    if($Selection.SignalGraph.Assembly.Sha256 -cne '85339B76A68132E56EB2649FACA825EB10F623938CF618E19507D5C5AFDFF713' -or $Selection.SignalGraph.Assembly.Identity -cne 'SignalGraph, Version=3.0.0.0, Culture=neutral, PublicKeyToken=null'){throw 'ST_NATIVE_PACKET: canonical 3.0 pin required'}
    $root=Resolve-STSelectionPath $Selection.Foundation.Root -Directory
    $manifest=Resolve-STSelectionPath $Selection.Foundation.Manifest
    if((Split-Path $manifest) -ne $root -or (Split-Path $manifest -Leaf) -cne 'SovereignTrust.Foundation.psd1'){throw 'ST_NATIVE_PACKET: manifest mismatch'}
    $files=@(Get-ChildItem $root -Recurse -Force -File);$dirs=@(Get-ChildItem $root -Recurse -Force -Directory)
    if($files.Count -ne $Selection.Foundation.Files.Count -or $dirs.Count -ne $Selection.Foundation.Directories.Count){throw 'ST_NATIVE_PACKET: membership mismatch'}
    $members=@{};foreach($entry in $Selection.Foundation.Files){if($members.ContainsKey($entry.Path) -or $entry.Path -match '(^|/)\.\.(/|$)' -or [IO.Path]::IsPathFullyQualified($entry.Path)){throw 'ST_NATIVE_PACKET: invalid member'};$members[$entry.Path]=$entry}
    foreach($file in $files){$null=Resolve-STSelectionPath $file.FullName;$rel=[IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/');$entry=$members[$rel];if($null -eq $entry -or $file.Length -ne $entry.Length -or (Get-FileHash $file.FullName).Hash -ne $entry.Sha256){throw "ST_NATIVE_PACKET: source drift $rel"}}
    foreach($dir in $dirs){$null=Resolve-STSelectionPath $dir.FullName -Directory;if([IO.Path]::GetRelativePath($root,$dir.FullName).Replace('\','/') -notin $Selection.Foundation.Directories){throw 'ST_NATIVE_PACKET: directory drift'}}
    $assemblies=@($Selection.SignalGraph.Assembly)+@($Selection.SignalGraph.Dependencies)
    if($Selection.Foundation.NativeCore){$assemblies+=@($Selection.Foundation.NativeCore)}
    foreach($entry in $assemblies){
        $path=Resolve-STSelectionPath $entry.Path
        if((Get-Item $path).Length -ne $entry.Length -or (Get-FileHash $path).Hash -ne $entry.Sha256 -or [Reflection.AssemblyName]::GetAssemblyName($path).FullName -cne $entry.Identity){throw 'ST_NATIVE_PACKET: assembly drift'}
        $actual=@([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object FullName -CEQ $entry.Identity)
        if($actual.Count -gt 1 -or ($RequireLoaded -and $actual.Count -ne 1)){throw 'ST_NATIVE_DEPENDENCY: actual assembly count mismatch'}
        foreach($assembly in $actual){if($assembly.Location -ne $entry.Path -or -not [object]::ReferenceEquals([Runtime.Loader.AssemblyLoadContext]::GetLoadContext($assembly),[Runtime.Loader.AssemblyLoadContext]::Default)){throw 'ST_NATIVE_DEPENDENCY: actual loaded origin/context mismatch'}}
    }
    if(@(Get-Module -All SignalGraph).Count){throw 'ST_NATIVE_TYPE: PowerShell SignalGraph module forbidden'}
    foreach($asm in [AppDomain]::CurrentDomain.GetAssemblies()){
        foreach($name in 'Signal','Graph','SignalEntry'){if($asm.GetType($name,$false)){throw 'ST_NATIVE_TYPE: legacy SignalGraph family forbidden'}}
        $native=$asm.GetType('SignalGraph.Signal',$false)
        if($native -and ($native.Assembly.Location -ne $Selection.SignalGraph.Assembly.Path -or $native.Assembly.FullName -cne $Selection.SignalGraph.Assembly.Identity -or -not [object]::ReferenceEquals([Runtime.Loader.AssemblyLoadContext]::GetLoadContext($native.Assembly),[Runtime.Loader.AssemblyLoadContext]::Default))){throw 'ST_NATIVE_TYPE: wrong canonical type origin/context'}
    }
    Assert-STNativeAdapterClosure $Selection
    $loaded=@(Get-Module -All SovereignTrust.Foundation)
    if($loaded.Count -gt 1 -or ($RequireLoaded -and $loaded.Count -ne 1)){throw "ST_NATIVE_MODULE: count=$($loaded.Count), require=$RequireLoaded, paths=$($loaded.Path -join '|')"}
    foreach($module in $loaded){if($module.ModuleBase -ne $root){throw 'ST_NATIVE_MODULE: wrong origin'}}
}
function Get-STFoundationSelection {
    param([string]$LegacyManifest,$SelectionPacket,[string]$SelectionState)
    if($null -eq $SelectionPacket){$SelectionPacket=Read-STSelectionPacket $env:ST_FOUNDATION_SELECTION_PACKET $env:ST_FOUNDATION_SELECTION_SHA256}
    Assert-STFoundationSelection $SelectionPacket
    if($env:ST_FOUNDATION_MANIFEST -ne $SelectionPacket.Foundation.Manifest){throw 'ST_NATIVE_MODULE: explicit selection mismatch'}
    $SelectionPacket
}
function Get-STSelectedDiscoveryPath {
    param($Selection)
    $roots=@((Join-Path $PSHOME Modules))
    if($IsWindows){$roots+=Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'PowerShell/Modules';$roots+=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell/Modules'}
    $roots -join [IO.Path]::PathSeparator
}
function Assert-STSelectedDiscovery {param($Selection) if($env:PSModulePath -cne (Get-STSelectedDiscoveryPath $Selection)){throw 'ST_NATIVE_DISCOVERY: unexpected path'}}
function Initialize-STSelectedProcessDiscovery {param($Selection) Assert-STSelectedDiscovery $Selection;Initialize-STSelectedDependency $Selection}
function Initialize-STSelectedDependency {
    param($Selection)
    Assert-STFoundationSelection $Selection
    $global:PSModuleAutoLoadingPreference='None'
    $assemblies=@($Selection.SignalGraph.Dependencies)+@($Selection.SignalGraph.Assembly)
    if($Selection.Foundation.NativeCore){$assemblies+=@($Selection.Foundation.NativeCore)}
    foreach($entry in $assemblies){
        $matches=@([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object FullName -CEQ $entry.Identity)
        if($matches.Count -gt 1){throw 'ST_NATIVE_DEPENDENCY: duplicate identity'}
        if($matches.Count){if($matches[0].Location -ne $entry.Path -or -not [object]::ReferenceEquals([Runtime.Loader.AssemblyLoadContext]::GetLoadContext($matches[0]),[Runtime.Loader.AssemblyLoadContext]::Default)){throw 'ST_NATIVE_DEPENDENCY: actual loaded origin/context mismatch'}}
        else{[void][Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath($entry.Path)}
    }
    Assert-STFoundationSelection $Selection
}
function Import-STSelectedFoundation {
    param($Selection)
    Initialize-STSelectedDependency $Selection
    if(-not (Get-Module SovereignTrust.Foundation)){Import-Module $Selection.Foundation.Manifest -Global -ErrorAction Stop}
    Assert-STFoundationSelection $Selection -RequireLoaded
}
function Get-STSelectionProvenance {
    param($Selection)
    Assert-STFoundationSelection $Selection -RequireLoaded
    $type=[type]::GetType('SignalGraph.Signal, SignalGraph',$true);$asm=$type.Assembly
    $dependencies=@(foreach($entry in $Selection.SignalGraph.Dependencies){$actual=@([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object FullName -CEQ $entry.Identity)[0];[ordered]@{Identity=$actual.FullName;Path=$actual.Location;Sha256=(Get-FileHash $actual.Location).Hash;LoadContext=[Runtime.Loader.AssemblyLoadContext]::GetLoadContext($actual).Name;ExpectedSha256=$entry.Sha256}})
    $core=$null
    if($Selection.Foundation.NativeCore){$coreType=[type]::GetType('SovereignTrust.Foundation.Classes.Conduction.Conductor, SovereignTrust.Foundation',$true);$core=[ordered]@{Path=$coreType.Assembly.Location;Identity=$coreType.Assembly.FullName;Sha256=(Get-FileHash $coreType.Assembly.Location).Hash;LoadContext=[Runtime.Loader.AssemblyLoadContext]::GetLoadContext($coreType.Assembly).Name}}
    [pscustomobject]@{ProcessId=$PID;FoundationPath=(Get-Module SovereignTrust.Foundation).Path;SignalGraphPath=$asm.Location;SignalType=$type.AssemblyQualifiedName;SignalModule=$type.Module.Name;SignalSource=$Selection.SignalGraph.Assembly.Path;PacketSha256=$Selection.PacketSha256;LoadContext=[Runtime.Loader.AssemblyLoadContext]::GetLoadContext($asm).Name;Dependencies=$dependencies;NativeCore=$core}
}
function Assert-STSelectedEntryPoint {
    param($Selection,[string]$EntryPoint)
    Assert-STNativeAdapterClosure $Selection
    $path=Resolve-STSelectionPath $EntryPoint
    $matches=@(foreach($entry in @($Selection.AdapterModules)){foreach($relative in $entry.EntryPoints){if([IO.Path]::GetFullPath((Join-Path $entry.Root $relative)) -ieq $path){$entry}}})
    if($matches.Count -ne 1 -or [IO.Path]::GetExtension($path) -cne '.psd1'){throw 'ST_NATIVE_ENTRYPOINT: manifest not in exact selected development closure'}
    $data=Import-PowerShellDataFile -LiteralPath $path
    if(@($data.RequiredModules|Where-Object {$null -ne $_}).Count){throw 'ST_NATIVE_ENTRYPOINT: unreviewed module dependency'}
    foreach($script in @($data.ScriptsToProcess)){
        $scriptPath=[IO.Path]::GetFullPath((Join-Path (Split-Path $path) $script))
        if($scriptPath -notin @($Selection.AdapterBootstraps.Path)){throw 'ST_NATIVE_ENTRYPOINT: bootstrap not selected'}
    }
}
function New-STSelectedRunspace {
    param($Selection)
    Assert-STSelectedDiscovery $Selection
    $runspace=[runspacefactory]::CreateRunspace();$runspace.Open();$ps=[powershell]::Create()
    try{
        $ps.Runspace=$runspace
        $null=$ps.AddScript({param($helper,$packet,$sha) try{. $helper;$selection=Read-STSelectionPacket $packet $sha;Import-STSelectedFoundation $selection;Get-STSelectionProvenance $selection}catch{throw "$($_.Exception.Message) STACK $($_.ScriptStackTrace)"}}.ToString()).AddArgument((Join-Path $PSScriptRoot STFoundationSelection.ps1)).AddArgument($Selection.PacketPath).AddArgument($Selection.PacketSha256)
        $result=@($ps.Invoke());if($ps.HadErrors -or $result.Count -ne 1){throw "ST_NATIVE_WORKER: $($ps.Streams.Error|Out-String)"}
        $runspace|Add-Member STSelectionProvenance $result[0];$runspace
    }catch{$runspace.Dispose();throw}finally{$ps.Dispose()}
}
function Get-STWorkerSelection {param([string]$FoundationModulePath) $selection=Get-STFoundationSelection;if($FoundationModulePath -and $FoundationModulePath -ne $selection.Foundation.Manifest){throw 'ST_NATIVE_WORKER: manifest mismatch'};Assert-STFoundationSelection $selection -RequireLoaded;$selection}
function New-STSelectedInitialSessionState {
    param($Selection)
    $state=[Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach($entry in @(@('STWorkerPacket',$Selection.PacketPath),@('STWorkerSha',$Selection.PacketSha256),@('STWorkerKnownAssembly',$Selection.SignalGraph.Assembly.Identity),@('STWorkerExpectedDiscovery',(Get-STSelectedDiscoveryPath $Selection)))){$state.Variables.Add([Management.Automation.Runspaces.SessionStateVariableEntry]::new($entry[0],$entry[1],'Native selection'))}
    $null=$state.StartupScripts.Add((Join-Path $PSScriptRoot STFoundationWorker.ps1));$state
}

. "$PSScriptRoot/STNativeAdapterModules.ps1"
