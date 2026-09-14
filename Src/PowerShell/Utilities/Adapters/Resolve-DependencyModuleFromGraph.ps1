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
    # ░▒▓█ MODULE CLASS RESOLUTION █▓▒░
    $fullTypeSignal = Resolve-PathFromDictionary -Dictionary $manifestSignal -Path "@.FullType" | Select-Object -Last 1
    if ($opSignal.MergeSignalAndVerifyFailure($fullTypeSignal)) {
        $opSignal.LogCritical("❌ Failed to resolve FullType from module manifest.")
        return $opSignal
    }

    $className = $fullTypeSignal.GetResult()
      $isAlreadyLoadedSignal = Test-IsClassDefined -ClassName $className | Select-Object -Last 1
    if ($opSignal.MergeSignalAndVerifyFailure($isAlreadyLoadedSignal)) {
        $opSignal.LogCritical("❌ Class check failed for type: $className")
        return $opSignal
    }

#    if ($isAlreadyLoadedSignal.HasResult() -or $className -eq "Storage_EmbeddedFileSystem") {
    if ($className -eq "Storage_EmbeddedFileSystem") {
         $jacketSignal.SetResult($isAlreadyLoadedSignal.GetResult())
        $opSignal.LogInformation("✅ Class '$className' already loaded; skipping import.")
        Write-Host("✅ Class '$className' already loaded; skipping import.")
    }
    else {
        Write-Host("❌ Loading Class '$className'...")
        
        $modNameSignal     = Resolve-PathFromDictionary -Dictionary $manifestSignal -Path "@.Name" | Select-Object -Last 1
        $relPathSignal     = Resolve-PathFromDictionary -Dictionary $manifestSignal -Path "@.RelativeFilePath" | Select-Object -Last 1
        $devPathSignal     = Resolve-PathFromDictionary -Dictionary $manifestSignal -Path "@.RelativeFilePath" | Select-Object -Last 1

        if (-not $opSignal.MergeSignalAndVerifySuccess(@($modNameSignal, $relPathSignal, $devPathSignal))) {
            $opSignal.LogCritical("❌ Required fields missing for module import.")
            return $opSignal
        }

        $modName = $modNameSignal.GetResult()
        $relPath = $relPathSignal.GetResult()
        $rootPath = $devPathSignal.GetResult()

        #$fullModulePath = Join-Path (Join-Path $rootPath $relPath)

        # ░▒▓█ CHECK AND IMPORT MODULE █▓▒░
#        $checkSignal = Test-ModuleLoaded -ModulesGraph $ConductionContext -ModuleName $modName | Select-Object -Last 1
#        $opSignal.MergeSignal($checkSignal)

#        if (-not $checkSignal.Success()) {
        if (-not $false) {
            try {

                $resolveDependency = Resolve-ModuleFromAdapter -Signal $Signal -Slot "ModuleRoots" -ModuleName $modName -RelativePath $relPath | Select-Object -Last 1

                if ($opSignal.MergeSignalAndVerifyFailure($resolveDependency)) {
                    $opSignal.LogCritical("❌ Failed to resolve module path for '$modName'.")
                    return $opSignal
                }

                # Review adding back in tracking of modules loaded.
                #$regSignal = Register-ModuleLoaded -ModulesGraph $ConductionContext -ModuleName $modName -FullPath $relPath -Version "1.0.0" | Select-Object -Last 1



                $opSignal.MergeSignal($regSignal)
                $opSignal.LogInformation("📦 Module '$modName' loaded successfully from '$fullModulePath'.")
            }
            catch {
                $opSignal.LogCritical("❌ Import failed for module '$modName': $($_.Exception.Message)")
                return $opSignal
            }
        }
        else {
            $opSignal.LogVerbose("✅ Module '$modName' already loaded.")
        }
    }


    $opSignal.SetResult($jacketSignal)
    return $opSignal
}
