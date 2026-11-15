
<# This should be moved to be the core of the Invoke-FabricateAdapter method? #>
function Resolve-AdapterFromJacket {
    param (
        [Parameter(Mandatory = $true)]
        [SignalGraph.Signal]$Signal,

        [Parameter(Mandatory)]
        [object]$ConductionContext,

        [Parameter(Mandatory)]
        [object]$Jacket
    )

    $opSignal = [SignalGraph.Signal]::Start("ResolveAdapter:$($Jacket.Name)") | Select-Object -Last 1

    try {
        # ░▒▓█ RESOLVE VIRTUAL PATH █▓▒░
        $virtualPathSignal = Resolve-PathFromDictionary -Dictionary $Jacket -Path "@.VirtualPath" | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($virtualPathSignal)) {
            $opSignal.LogCritical("Jacket is missing a valid VirtualPath.")
            return $opSignal
        }

        $wirePath = $virtualPathSignal.GetResult()

        # Normalize source Storage v2 before manifest defaults can add legacy fields.
        $sourceWasStorageV2 = $false
        $sourceWasEmbeddedV2 = $false
        $selectedEmbeddedAddresses = $null
        $storageFamily = $null
        $sourceWasRemainingV2 = $false
        $remainingFamily = $null
        if ([string]$wirePath -match '^SovereignTrust\.Adapters\.Storage\.(AzureStorageAccount|AzureKeyVault|EmbeddedFileSystem|LocalFileSystem)\.') {
            $storageFamily = $Matches[1]
            $sourceValue = $Jacket.GetResult($true)
            $sourceWasStorageV2 = $null -ne $sourceValue.PSObject.Properties['SchemaVersion'] -and
                $sourceValue.SchemaVersion -eq 2
            $storageResolution = Resolve-StorageResourceRoutesJacket -Jacket $sourceValue -Family $storageFamily -AllowUnresolved | Select-Object -Last 1
            if ($storageResolution.Failure() -or -not $storageResolution.HasResult()) {
                return $opSignal.MergeSignal($storageResolution).LogCritical('Storage jacket is invalid before merge.')
            }
            if ($sourceWasStorageV2) {
                if ($storageFamily -eq 'EmbeddedFileSystem') {
                    $sourceWasEmbeddedV2 = $true
                    $selectedEmbeddedAddresses = @($storageResolution.GetResult().Addresses)
                }
                $sourceClone = [SignalGraph.Signal]::Start('StorageJacketSource', $Jacket) | Select-Object -Last 1
                $sourceClone.SetResult($storageResolution.GetResult())
                $Jacket = $sourceClone
            }
        }

        if ([string]$wirePath -match '^SovereignTrust\.Adapters\.(Satellite\.AzureApplicationInsights|Queue\.AzureStorageQueue|Data\.AzureDataExplorer|Data\.AzureSql|Conduction\.ST)\.') {
            $remainingFamily = switch ($Matches[1]) {
                'Satellite.AzureApplicationInsights' { 'AzureApplicationInsights' }
                'Queue.AzureStorageQueue' { 'AzureStorageQueue' }
                'Data.AzureDataExplorer' { 'AzureDataExplorer' }
                'Data.AzureSql' { 'AzureSql' }
                'Conduction.ST' { 'Conduction_ST' }
            }
            $sourceValue = $Jacket.GetResult($true)
            $sourceWasRemainingV2 = $null -ne $sourceValue.PSObject.Properties['SchemaVersion'] -and
                $sourceValue.SchemaVersion -eq 2
            $remainingResolution = Resolve-RemainingResourceRoutesJacket -Jacket $sourceValue -Family $remainingFamily -AllowUnresolved | Select-Object -Last 1
            if ($remainingResolution.Failure() -or -not $remainingResolution.HasResult()) {
                return $opSignal.MergeSignal($remainingResolution).LogCritical('Adapter jacket is invalid before merge.')
            }
            if ($sourceWasRemainingV2) {
                $sourceClone = [SignalGraph.Signal]::Start('RemainingJacketSource', $Jacket) | Select-Object -Last 1
                $sourceClone.SetResult($remainingResolution.GetResult())
                $Jacket = $sourceClone
            }
        }

        # ░▒▓█ LOAD MODULE MANIFEST GRAPH █▓▒░
        $moduleGraphSignal = Resolve-DependencyModuleFromGraph -Signal $Signal -ConductionContext $ConductionContext -WirePath $wirePath | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($moduleGraphSignal)) {
            $opSignal.LogCritical("Failed to load manifest from WirePath: $wirePath")
            return $opSignal
        }

        # ░▒▓█ RESOLVE CLASS TYPE FROM MANIFEST █▓▒░
        $typeSignal = Resolve-PathFromDictionary -Dictionary $moduleGraphSignal -Path "@.%.@.FullType" | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($typeSignal)) {
            $opSignal.LogCritical("Class name missing in manifest.")
            return $opSignal
        }

        $typeName = $typeSignal.GetResult()

        # ░▒▓█ RESOLVE CLASS TYPE FROM MANIFEST █▓▒░
        $instance = $null
        $error1 = $null
        $error2 = $null


        # ░▒▓█ INSTANCE CREATION █▓▒░
        if ($moduleGraphSignal.HasResult()) {
            $typeClass = $moduleGraphSignal.GetResult()
            while ($typeClass -is [SignalGraph.Signal] -and $typeClass.HasResult()) {
                $typeClass = $typeClass.GetResult() | Select-Object -Last 1
            }

            if ($typeClass -is [Type]) {
                $instance = [System.Activator]::CreateInstance($typeClass)
            }
        }

        if ($opSignal.MergeSignalAndVerifyFailure($typeSignal)) {
            $opSignal.LogCritical("Class name missing in manifest.")
            return $opSignal
        }

        if ($null -eq $instance) {
            try {
                $instance = New-Object -TypeName $typeName -ErrorAction Stop
            }
            catch {
                $error1 = "Failed to instantiate type '$typeName': $_"
            }
        }

        if ($null -eq $instance) {
            try {
                $resolveFunctionName = "Resolve-$typeName"
                $instance = & $resolveFunctionName
            }
            catch {
                $error2 = "Failed to instantiate type '$typeName': $_"
            }
        }

        if ($null -eq $instance) {
            $opSignal.LogCritical($error1)
            $opSignal.LogCritical($error2)
            return $opSignal
        }

        # ░▒▓█ TODO: THIS SHOULD BE DONE EXTERNALLY USING THE GRAPH CONDENSER █▓▒░

        # ░▒▓█ MERGE $JACKET OVER $MANIFEST █▓▒░
        $manifestSignal = Resolve-PathFromDictionary -Dictionary $moduleGraphSignal -Path "@.%.@" | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($manifestSignal)) {
            $opSignal.LogCritical("Failed to extract Manifest dictionary from Graph.")
            return $opSignal
        }

        $mergeServiceSignal = Resolve-PathFromDictionary -Dictionary $ConductionContext -Path "%.*.#.Adapters.*.#.MappedCondenser.@.$.*.#.MergeCondenser.@" | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($mergeServiceSignal) -or -not $mergeServiceSignal.HasResult()) {
            $opSignal.LogCritical("MergeCondenser not available on ConductionContext.")
            return $opSignal
        }

        $mergePlan= [PSCustomObject]@{
            
        }

        # Change this to memory generator call to merge and then run hydration in deferred
        $mergeItemSignal = [SignalGraph.Signal]::Start("MergeSignal") | Select-Object -Last 1
        Add-PathToDictionary -Dictionary $mergeItemSignal -Path "@.Base" -Value $manifestSignal.GetResult($true)  | Select-Object 
        Add-PathToDictionary -Dictionary $mergeItemSignal -Path "@.Overlay" -Value $Jacket.GetResult($true)  | Select-Object 

        $mergeService = $mergeServiceSignal.GetResult()
        if ($null -eq $mergeService -or -not ($mergeService | Get-Member -Name 'Invoke' -MemberType Method)) {
            $opSignal.LogCritical("MergeCondenser resolved without an invokable adapter instance.")
            return $opSignal
        }
        $mergeItemSignalJacket = [SignalGraph.Signal]::Start("MergeSignal") | Select-Object -Last 1
        $mergeItemSignalJacket.SetJacket($mergeItemSignal)

        $mergedSignal = $mergeService.Invoke("Merge", "Merge", $Signal, $mergePlan, $mergeItemSignalJacket) | Select-Object -Last 1 #$manifestSignal.GetResult(), $Jacket, $true) | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure($mergedSignal)) {
            if ($sourceWasRemainingV2 -or $sourceWasEmbeddedV2) { return $opSignal.LogCritical('Adapter v2 jacket merge failed.') }
            $opSignal.LogWarning("Jacket-to-Manifest merge failed; continuing with original jacket.")
        }
        else {
            $Jacket = $mergedSignal.GetResult()
            $opSignal.LogInformation("🧬 Jacket successfully merged over Manifest.")
        }
        if ($sourceWasEmbeddedV2) {
            if ($null -eq $Jacket -or $null -eq $Jacket.PSObject.Properties['Addresses']) {
                return $opSignal.LogCritical('Embedded v2 selected roots could not be restored after merge.')
            }
            $Jacket.Addresses = @($selectedEmbeddedAddresses)
            $restored = @($Jacket.Addresses)
            if ($restored.Count -ne $selectedEmbeddedAddresses.Count) {
                return $opSignal.LogCritical('Embedded v2 selected root count changed after merge.')
            }
            for ($i = 0; $i -lt $restored.Count; $i++) {
                if ($restored[$i] -cne $selectedEmbeddedAddresses[$i]) {
                    return $opSignal.LogCritical('Embedded v2 selected root order changed after merge.')
                }
            }
            $mergedSignal.SetResult($Jacket)
        }
        if ($sourceWasRemainingV2) {
            $selected = $remainingResolution.GetResult()
            $Jacket.Addresses = @($selected.Addresses)
            if ($remainingFamily -ne 'Conduction_ST') { $Jacket.Resource = $selected.Resource }
            elseif ($null -ne $Jacket.PSObject.Properties['Resource']) { $Jacket.PSObject.Properties.Remove('Resource') }
        }

        # $Jacket needs to be hydrated after the merge for any tokens that couldn't be hydrated during load and required deferred token lookups
#        if ($HydrationPlanSignal.HasResult()) {
            $HydrationSignal= [SignalGraph.Signal]::Start("Resolve-AdapterFromJacket.Invoke.Hydrate", $Jacket) | Select-Object -Last 1
            $HydrationSignal.SetJacket($mergedSignal)
#            $HydrationSignal.SetPointer($ItemSignal.GetPointer())

            $HydrationPlan = [PSCustomObject]@{
                    Path = "%.@"
                    HydrationPlan = "@"
                    HydrationStyle = "Deferred"
                }

            # Perform Hydration
            $StepResultSignal = Invoke-CondenserAdapter -Slot "Hydration" -Activity "Invoke" -Plan $HydrationPlan -Signal $Signal -ItemSignal $HydrationSignal | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure($StepResultSignal)) { return $opSignal }

            $Jacket = $StepResultSignal.GetResult()
 #       }

        if ($sourceWasStorageV2) {
            $storageHydrated = Resolve-StorageResourceRoutesJacket -Jacket $Jacket -Family $storageFamily -ValidateNormalizedV2 | Select-Object -Last 1
            if ($storageHydrated.Failure() -or -not $storageHydrated.HasResult()) {
                return $opSignal.MergeSignal($storageHydrated).LogCritical('Storage v2 hydration is incomplete.')
            }
        }
        if ($sourceWasRemainingV2) {
            $remainingHydrated = Resolve-RemainingResourceRoutesJacket -Jacket $Jacket -Family $remainingFamily -ValidateNormalizedV2 | Select-Object -Last 1
            if ($remainingHydrated.Failure() -or -not $remainingHydrated.HasResult()) {
                return $opSignal.MergeSignal($remainingHydrated).LogCritical('Adapter v2 hydration is incomplete.')
            }
        }



        # ░▒▓█ CONSTRUCT METHOD (OPTIONAL) █▓▒░
        if ($instance -and ($instance | Get-Member -Name "Construct" -MemberType Method)) {
            $constructCall = $instance.Construct($Jacket)
            $constructSignal = $constructCall | Select-Object -Last 1

            if ($opSignal.MergeSignalAndVerifySuccess($constructSignal)) {
                $opSignal.LogInformation("✅ Adapter '$($Jacket.Name)' ($($Jacket.VirtualPath)) constructed successfully.")
            }
            else {
                $opSignal.LogWarning("Construct() failed on adapter '$($Jacket.Name)'.")
            }
        }
        else {
            $opSignal.LogVerbose("No Construct() method found for '$($Jacket.Name)'. ($($Jacket.VirtualPath)) Proceeding without initialization.")
        }

        # ░▒▓█ RESULT █▓▒░
            $opSignal.SetResult($instance)
        $opSignal.LogInformation("📦 Adapter '$($Jacket.Name)' resolved and returned successfully.")
    }
    catch {
        $opSignal.LogCritical("🔥 Exception during adapter resolution: $($_.Exception.Message)", $null, $_.Exception)
    }

    return $opSignal
}
