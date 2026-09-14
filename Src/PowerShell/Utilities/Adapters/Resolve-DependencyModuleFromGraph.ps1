function Resolve-DependencyModuleFromGraph {
    param (
        [Parameter(Mandatory = $true)]
        [Signal]$Signal,

        [Parameter(Mandatory = $true)]
        [object]$ConductionContext,

        [Parameter(Mandatory = $true)]
        [string]$WirePath
    )

    $opSignal = [Signal]::Start("Resolve-DependencyModuleFromGraph:$WirePath") | Select-Object -Last 1

    # ░▒▓█ RESOLVE MODULE SIGNAL █▓▒░
    $pathFormulaSignal = Resolve-ModulePathSignal -WirePath $WirePath | Select-Object -Last 1
    if (-not $opSignal.MergeSignalAndVerifySuccess($pathFormulaSignal)) {
        $opSignal.LogCritical("❌ Failed to resolve module signal from wire path: $WirePath")
        return $opSignal
    }

    # ░▒▓█ GET MODULE JACKET █▓▒░
    $jacketSignal = $pathFormulaSignal.GetResult()
    $manifestSignalWrapper = Resolve-PathFromDictionary -Dictionary $jacketSignal -Path "%" | Select-Object -Last 1
    if (-not $opSignal.MergeSignalAndVerifySuccess($manifestSignalWrapper)) {
        $opSignal.LogCritical("❌ Could not retrieve manifest structure from jacket signal.")
        return $opSignal
    }

    $manifestSignal = $manifestSignalWrapper.GetResult()

    # Resolve and import the module only. Adapter class construction belongs to
    # the first-use path, after the adapter content has been registered.
    $modNameSignal = Resolve-PathFromDictionary -Dictionary $manifestSignal -Path "@.Name" | Select-Object -Last 1
    $relPathSignal = Resolve-PathFromDictionary -Dictionary $manifestSignal -Path "@.RelativeFilePath" | Select-Object -Last 1
    if (-not $opSignal.MergeSignalAndVerifySuccess(@($modNameSignal, $relPathSignal))) {
        $opSignal.LogCritical("❌ Required fields missing for module import.")
        return $opSignal
    }

    $modName = [string]$modNameSignal.GetResult()
    $relPath = [string]$relPathSignal.GetResult()

    # Foundation dot-sources this storage implementation. It is also the
    # adapter used to resolve ModuleRoots, so trying to load it through the
    # storage adapter would recurse before the runtime has been mounted.
    if ($modName -eq 'Storage_EmbeddedFileSystem.psd1') {
        $opSignal.LogInformation("✅ Bootstrap module '$modName' is already available.")
        $opSignal.SetResult($jacketSignal)
        return $opSignal
    }

    $resolveDependency = Resolve-ModuleFromAdapter -Signal $Signal -Slot "ModuleRoots" -ModuleName $modName -RelativePath $relPath | Select-Object -Last 1
    if ($opSignal.MergeSignalAndVerifyFailure($resolveDependency)) {
        $opSignal.LogCritical("❌ Failed to resolve module path for '$modName'.")
        return $opSignal
    }

    $opSignal.LogInformation("📦 Module '$modName' imported successfully.")


    $opSignal.SetResult($jacketSignal)
    return $opSignal
}
