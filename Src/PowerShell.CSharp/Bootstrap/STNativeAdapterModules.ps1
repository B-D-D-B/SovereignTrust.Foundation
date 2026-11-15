# Generic selected development-module closure. No provider registration lives here.
function Assert-STNativeAdapterClosure {
    param($Selection)
    foreach($entry in @($Selection.AdapterModules)) {
        $root=Resolve-STSelectionPath $entry.Root -Directory
        if((Split-Path $root -Leaf) -cne 'PowerShell.CSharp'){throw 'ST_NATIVE_ADAPTER: development root required'}
        $files=@(Get-ChildItem $root -Recurse -Force -File)
        $dirs=@(Get-ChildItem $root -Recurse -Force -Directory)
        if($files.Count -ne $entry.Files.Count -or $dirs.Count -ne $entry.Directories.Count){throw 'ST_NATIVE_ADAPTER: membership drift'}
        $members=@{}
        foreach($row in $entry.Files){if($members.ContainsKey($row.Path)){throw 'ST_NATIVE_ADAPTER: duplicate member'};$members[$row.Path]=$row}
        foreach($file in $files){
            $null=Resolve-STSelectionPath $file.FullName
            $relative=[IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/')
            $match=$members[$relative]
            if($null -eq $match -or $file.Length -ne $match.Length -or (Get-FileHash $file.FullName).Hash -cne $match.Sha256){throw "ST_NATIVE_ADAPTER: file drift $relative"}
        }
        foreach($dir in $dirs){$null=Resolve-STSelectionPath $dir.FullName -Directory;if([IO.Path]::GetRelativePath($root,$dir.FullName).Replace('\','/') -cnotin $entry.Directories){throw 'ST_NATIVE_ADAPTER: directory drift'}}
    }
    foreach($entry in @($Selection.AdapterBootstraps)){
        $path=Resolve-STSelectionPath $entry.Path
        if((Get-FileHash $path).Hash -cne $entry.Sha256){throw 'ST_NATIVE_ADAPTER: bootstrap drift'}
    }
}
function Get-STNativeAdapterEntry {
    param($Selection,[string]$WirePath)
    $parts=$WirePath.Split('.')
    if($parts.Count -lt 4){throw 'ST_NATIVE_ADAPTER: invalid wire path'}
    $repository=$parts[0]+'.'+$parts[1]
    $entries=@($Selection.AdapterModules|Where-Object { $_.Repository -ieq $repository -and $_.Kind -ieq $parts[2] -and $_.Provider -ieq $parts[3] })
    if($entries.Count -ne 1){throw "ST_NATIVE_ADAPTER: no unique selected module for $repository/$($parts[2])/$($parts[3])"}
    $entries[0]
}
function Resolve-STNativeAdapterType {
    param($Selection,[string]$WirePath,[string]$FullType)
    $entry=Get-STNativeAdapterEntry $Selection $WirePath
    if($FullType -cne ($entry.Kind+'_'+$entry.Provider)){throw 'ST_NATIVE_ADAPTER: class does not match selected module declaration contract'}
    if($entry.EntryPoints.Count -ne 1){throw 'ST_NATIVE_ADAPTER: no unique manifest entrypoint'}
    $path=Join-Path $entry.Root $entry.EntryPoints[0]
    Assert-STSelectedEntryPoint $Selection $path
    $null=Import-Module -Name $path -Global -PassThru -ErrorAction Stop
    Assert-STFoundationSelection $Selection -RequireLoaded
    $data=Import-PowerShellDataFile -LiteralPath $path
    $rootModule=[IO.Path]::GetFullPath((Join-Path (Split-Path $path) $data.RootModule))
    $modules=@(Get-Module -All|Where-Object { $_.Path -and [IO.Path]::GetFullPath($_.Path) -ieq $rootModule })
    if($modules.Count -ne 1){throw 'ST_NATIVE_ADAPTER: canonical module count mismatch'}
    $module=$modules[0]
    # PS 7.6 module metadata retains the compiled declaration AST. Bind its
    # actual Type, not the ambient PSTypeName resolver's first matching type.
    $flags=[Reflection.BindingFlags]'Instance,Public,NonPublic'
    $getDefinitions=[Management.Automation.PSModuleInfo].GetMethod('GetExportedTypeDefinitions',$flags)
    $typeProperty=[Management.Automation.Language.TypeDefinitionAst].GetProperty('Type',$flags)
    if($null -eq $getDefinitions -or $null -eq $typeProperty){throw 'ST_NATIVE_ADAPTER: selected host cannot prove class declaration ownership'}
    $definitions=$getDefinitions.Invoke($module,@())
    $candidates=@($definitions.Values)
    # Dot-sourced class files are not exported type definitions. Their loaded
    # function ScriptBlock AST retains the same compiled declaration and origin.
    $functions=@($module.ExportedFunctions.Values)+@(& $module {Get-Command Get-STNativeAdapterClassDeclaration -CommandType Function -ErrorAction SilentlyContinue})
    foreach($function in $functions){
        $ast=$function.ScriptBlock.Ast
        while($null -ne $ast.Parent){$ast=$ast.Parent}
        $candidates+=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.TypeDefinitionAst]},$true))
    }
    $declarations=@($candidates|Where-Object {$_.Name -ceq $FullType -and $_.IsClass}|Sort-Object @{Expression={$_.Extent.File}},@{Expression={$_.Extent.StartOffset}} -Unique)
    if($declarations.Count -ne 1){throw 'ST_NATIVE_ADAPTER: unique selected class declaration required'}
    $declaration=$declarations[0]
    $declaredPath=[IO.Path]::GetFullPath($declaration.Extent.File)
    $declaredRelative=[IO.Path]::GetRelativePath($entry.Root,$declaredPath).Replace('\','/')
    if($declaredRelative -match '^\.\.' -or $declaredRelative -cnotin $entry.Files.Path){throw 'ST_NATIVE_ADAPTER: class declaration belongs to another module'}
    $declaredType=$typeProperty.GetValue($declaration)
    $resolved=@(& $module {param($name) ([Management.Automation.PSTypeName]$name).Type} $FullType)
    if($resolved.Count -ne 1 -or $resolved[0] -isnot [type]){throw "ST_NATIVE_ADAPTER: selected class unavailable: $FullType"}
    if(-not [object]::ReferenceEquals($declaredType,$resolved[0])){throw 'ST_NATIVE_ADAPTER: ambient type differs from selected compiled declaration'}
    foreach($method in $resolved[0].GetMethods()){
        foreach($parameterType in @($method.ReturnType)+@($method.GetParameters()|ForEach-Object ParameterType)){
            if($parameterType.FullName -in 'Signal','Graph','SignalEntry'){throw 'ST_NATIVE_ADAPTER: legacy parameter/return family forbidden'}
            if($parameterType.FullName -like 'SignalGraph.*' -and $parameterType.Assembly.Location -ine $Selection.SignalGraph.Assembly.Path){throw 'ST_NATIVE_ADAPTER: noncanonical parameter/return type owner'}
        }
    }
    $resolved[0]
}
