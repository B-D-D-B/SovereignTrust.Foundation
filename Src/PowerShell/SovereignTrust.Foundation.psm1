using module SignalGraph
    # Import shared functions for Map Condensers

    $mapSharedPath = Join-Path $PSScriptRoot "Utilities/Adapters/Condenser/Map/MapCondenser.Shared.psm1"
    Import-Module (Resolve-Path $mapSharedPath).ProviderPath -Force
function Start-SignalWrapper(
         [string]$Name,
        [object]$ReversePointer = $null
   ) {
    return Start-Signal -Name $Name -ReversePointer $ReversePointer
}

function Invoke-Telemetry(
    [Signal]$Signal,
    [Signal]$ItemSignal
){
    Invoke-MappedAdapter -Adapter "Network.Telemetry" -Activity "EmitSignalFull" -Signal $Signal -Plan ([pscustomobject]@{}) -ItemSignal $ItemSignal
}

# Load all files (functions + classes)
. "$PSScriptRoot/Wrappers/Adapters/Condenser/Invoke-ConductionCondenser.ps1"

. "$PSScriptRoot/Wrappers/Adapters/Condenser/Invoke-FabCondenser.ps1"
. "$PSScriptRoot/Wrappers/Adapters/Condenser/Invoke-TransformCondenser.ps1"
. "$PSScriptRoot/Wrappers/Adapters/Condenser/Invoke-HydrationCondenser.ps1"

. "$PSScriptRoot/Wrappers/Adapters/Condenser/Invoke-TokenCondenser.ps1"
. "$PSScriptRoot/Wrappers/Adapters/Condenser/Invoke-PlanCondenser.ps1"


. "$PSScriptRoot/Wrappers/Adapters/Invoke-CondenserAdapter.ps1"
. "$PSScriptRoot/Wrappers/Adapters/Invoke-MappedAdapter.ps1"

. "$PSScriptRoot/Classes/Adapters/MappedDataAdapter.ps1"
. "$PSScriptRoot/Classes/Adapters/MappedStorageAdapter.ps1"
. "$PSScriptRoot/Classes/Adapters/MappedTokenAdapter.ps1"
. "$PSScriptRoot/Classes/Adapters/MappedAdapterTemplate.ps1"
. "$PSScriptRoot/Classes/Adapters/MappedConductionAdapter.ps1"
. "$PSScriptRoot/Classes/Adapters/MappedCondenserAdapter.ps1"
. "$PSScriptRoot/Classes/Adapters/MappedConduitAdapter.ps1"
. "$PSScriptRoot/Classes/Adapters/MappedNetworkAdapter.ps1"
. "$PSScriptRoot/Classes/Adapters/MappedQueueAdapter.ps1"
. "$PSScriptRoot/Classes/Adapters/MappedQuantumAdapter.ps1"
. "$PSScriptRoot/Classes/Adapters/MappedTelemetryAdapter.ps1"
. "$PSScriptRoot/Classes/Adapters/MappedSessionAdapter.ps1"
. "$PSScriptRoot/Classes/Adapters/MappedUtilityAdapter.ps1"
. "$PSScriptRoot/Classes/Conduction/Conduit.ps1"
. "$PSScriptRoot/Classes/Conduction/Conductor.ps1"

. "$PSScriptRoot/Classes/Adapters/Token/Token_System.ps1"
. "$PSScriptRoot/Classes/Adapters/Token/Token_Memory.ps1"
. "$PSScriptRoot/Classes/Adapters/Token/Token_Dynamic.ps1"
. "$PSScriptRoot/Classes/Adapters/Token/Token_Conduction.ps1"
. "$PSScriptRoot/Classes/Adapters/Token/Token_Environment.ps1"
. "$PSScriptRoot/Classes/Adapters/Token/Token_Formatter.ps1"
. "$PSScriptRoot/Classes/Adapters/Token/Token_Generator.ps1"
. "$PSScriptRoot/Classes/Adapters/Token/Token_Navigator.ps1"
. "$PSScriptRoot/Classes/Adapters/Token/Token_Storage.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Rest/Resolve-BearerToken.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Rest/Invoke-RestCondenserCore.ps1"

. "$PSScriptRoot/Utilities/Adapters/Condenser/Plan/Resolve-ClonePlan.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Plan/Invoke-PlanIteration.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Plan/Invoke-PlanIterationWorker.ps1"
. "$PSScriptRoot/Utilities/Threading/Invoke-STRunspacePool.ps1"

. "$PSScriptRoot/Utilities/Adapters/Storage/Invoke-MappedStorageAdapter.ps1"
. "$PSScriptRoot/Utilities/Adapters/Invoke-MappedAdapterCore.ps1"

. "$PSScriptRoot/Utilities/Adapters/Network/Invoke-NetworkAdapter.ps1"

. "$PSScriptRoot/Classes/Adapters/BaseAdapter.ps1"
#. "$PSScriptRoot/Classes/Adapters/Conduit.ps1"
. "$PSScriptRoot/Classes/Adapters/Storage/Storage_EmbeddedFileSystem.ps1"

. "$PSScriptRoot/Classes/Adapters/Telemetry/ConsoleLogger.ps1"
. "$PSScriptRoot/Classes/Adapters/Telemetry/SignalTelemeter.ps1"


. "$PSScriptRoot/Classes/Adapters/Condenser/RestCondenser.ps1"

. "$PSScriptRoot/Utilities/Adapters/Condenser/Format/Invoke-FormatJson.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Format/Invoke-FormatXml.ps1"

. "$PSScriptRoot/Classes/Adapters/Condenser/FabCondenser.ps1"
. "$PSScriptRoot/Classes/Adapters/Condenser/FormatCondenser.ps1"
. "$PSScriptRoot/Classes/Adapters/Condenser/ConductionCondenser.ps1"
. "$PSScriptRoot/Classes/Adapters/Condenser/GraphCondenser.ps1"
#. "$PSScriptRoot/Classes/Adapters/Condenser/GlobalCondenser.ps1"
#. "$PSScriptRoot/Classes/Adapters/Condenser/GridCondenser.ps1"
. "$PSScriptRoot/Classes/Adapters/Condenser/ConduitCondenser.ps1"
. "$PSScriptRoot/Classes/Adapters/Condenser/HydrationCondenser.ps1"
. "$PSScriptRoot/Classes/Adapters/Condenser/MapCondenser.ps1"
. "$PSScriptRoot/Classes/Adapters/Condenser/MemoryCondenser.ps1"
. "$PSScriptRoot/Classes/Adapters/Condenser/MergeCondenser.ps1"
. "$PSScriptRoot/Classes/Adapters/Condenser/TokenCondenser.ps1"
. "$PSScriptRoot/Classes/Adapters/Condenser/PlanCondenser.ps1"
. "$PSScriptRoot/Classes/Adapters/Condenser/TransformCondenser.ps1"

#. "$PSScriptRoot/Utilities/Adapters/Condenser/Rest/Resolve-BearerToken.ps1"
#. "$PSScriptRoot/Utilities/Adapters/Condenser/Rest/Invoke-RestApi.ps1"

. "$PSScriptRoot/Utilities/Adapters/Condenser/Transform/Invoke-TransformCondenserCore.ps1"

. "$PSScriptRoot/Utilities/Adapters/Condenser/Fab/Invoke-FabricateAdapter.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Fab/Invoke-GraphFabCondenser.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Fab/Resolve-ModuleFromAdapter.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Conduit/Invoke-ProcessConduitCondenser.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Conduit/Invoke-ConduitPool.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Grid/Invoke-GridCondenser.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Graph/Invoke-GraphCondenser.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Conduction/Invoke-ConductionCondenser.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Conduction/Invoke-GraphConductionCondenser.ps1"
#. "$PSScriptRoot/Utilities/Adapters/Condenser/Graph/Invoke-Graph.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Global/Invoke-GlobalCondenser.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Token/Invoke-JsonTokenCondenser.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Global/Resolve-TokenForProperty.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Hydration/Convert-VirtualPathToWirePath.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Hydration/Invoke-GraphHydrationCondenser.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Hydration/Invoke-ApplyHydrationCondenser.ps1"
#. "$PSScriptRoot/Utilities/Adapters/Condenser/Hydration/Read-HydrationFile.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Hydration/Resolve-GraphHydrationQueue.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Hydration/Resolve-HydrationSourcePath.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Memory/Invoke-HotPathResolution.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Memory/Invoke-MemoryCondenser.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Memory/Invoke-PathHydration.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Merge/Merge-CondenserCore.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Token/Invoke-HydrateTokenCondenser.ps1"


. "$PSScriptRoot/Utilities/Adapters/Condenser/Transform/Invoke-TransformSelect.ps1"
. "$PSScriptRoot/Utilities/Adapters/Condenser/Transform/Invoke-TransformInject.ps1"

#. "$PSScriptRoot/Utilities/New-Conductor.ps1"
. "$PSScriptRoot/Utilities/Adapters/Storage/Invoke-EmbeddedFileSystem_ReadObject.ps1"
. "$PSScriptRoot/Utilities/Adapters/Storage/Invoke-EmbeddedFileSystem_WriteObject.ps1"
. "$PSScriptRoot/Utilities/Json/Invoke-CloneItem.ps1"

. "$PSScriptRoot/Utilities/Adapters/New-MappedCondenserAdapterFromGraph.ps1"
. "$PSScriptRoot/Utilities/Adapters/New-AdapterRegistration.ps1"
. "$PSScriptRoot/Utilities/Adapters/Register-AdapterToMappedSlot.ps1"
. "$PSScriptRoot/Utilities/Adapters/Register-MappedAdapter.ps1"
. "$PSScriptRoot/Utilities/Adapters/Register-ModuleLoaded.ps1"
. "$PSScriptRoot/Utilities/Adapters/Resolve-AdaptersFromJacket.ps1"
. "$PSScriptRoot/Utilities/Adapters/Resolve-RegisteredAdapter.ps1"
. "$PSScriptRoot/Utilities/Adapters/Resolve-MappedAdapter.ps1"
. "$PSScriptRoot/Utilities/Adapters/Resolve-ConductorAdapters.ps1"
. "$PSScriptRoot/Utilities/Adapters/Resolve-DependencyModuleFromGraph.ps1"
. "$PSScriptRoot/Utilities/Adapters/Test-ModuleLoaded.ps1"

. "$PSScriptRoot/Utilities/Invoke-ST.ps1"

. "$PSScriptRoot/Utilities/Adapters/Storage/Resolve-ModulePathFromAdapter.ps1"
. "$PSScriptRoot/Utilities/Adapters/Storage/Resolve-PathWithExtensionFromPath.ps1"

#Turned off 1-3-26
#. "$PSScriptRoot/Utilities/Adapters/Invoke-MappedAdapter.ps1"
. "$PSScriptRoot/Utilities/Adapters/Token/Invoke-MappedTokenAdapter.ps1"
. "$PSScriptRoot/Utilities/Adapters/Token/Dynamic/Resolve-TokenDynamic.ps1"
. "$PSScriptRoot/Utilities/Adapters/Token/Invoke-TokenDynamic.ps1"
. "$PSScriptRoot/Utilities/Adapters/Token/Invoke-TokenSystem.ps1"
. "$PSScriptRoot/Utilities/Adapters/Token/Invoke-TokenMemory.ps1"
. "$PSScriptRoot/Utilities/Adapters/Token/Invoke-TokenEnvironment.ps1"
. "$PSScriptRoot/Utilities/Adapters/Token/Invoke-TokenFormatter.ps1"
. "$PSScriptRoot/Utilities/Adapters/Token/Invoke-TokenStorage.ps1"
. "$PSScriptRoot/Utilities/Adapters/Token/Invoke-TokenFormatterFilePath.ps1"
. "$PSScriptRoot/Utilities/Adapters/Token/Invoke-TokenFormatterVirtualFolder.ps1"
. "$PSScriptRoot/Utilities/Adapters/Token/Invoke-TokenFormatterJson.ps1"
. "$PSScriptRoot/Utilities/Adapters/Token/Invoke-TokenFormatterString.ps1"

. "$PSScriptRoot/Utilities/Resolve-SourcePathFromPlan.ps1"

##. "$PSScriptRoot/Utilities/Conduction/Complete-Conduction.ps1"
#. "$PSScriptRoot/Utilities/Conduction/ConductionCoreFunctions.ps1"
#. "$PSScriptRoot/Utilities/Conduction/ConductionPhaseFunctions.ps1"
#. "$PSScriptRoot/Utilities/Conduction/Convert-AgentAdaptersToConductor.ps1"
. "$PSScriptRoot/Utilities/Conduction/Get-AgentForConductor.ps1"
. "$PSScriptRoot/Utilities/Conduction/Invoke-Conduction.ps1"
#. "$PSScriptRoot/Utilities/Conduction/Resolve-RelativePathFromWirePath-na.ps1"
. "$PSScriptRoot/Utilities/Conduction/Start-Conduction.ps1"
. "$PSScriptRoot/Utilities/Conduction/Start-SovereignTrust.ps1"
. "$PSScriptRoot/Utilities/Conduction/Start-BondingConduction.ps1"
. "$PSScriptRoot/Utilities/Conduction/Resolve-Conduit.ps1"
. "$PSScriptRoot/Utilities/Conduction/Initialize-STEnvironment.ps1"
. "$PSScriptRoot/Utilities/Conduction/Resolve-Conductor.ps1"
. "$PSScriptRoot/Utilities/Graph/Convert-GraphToJson.ps1"
. "$PSScriptRoot/Utilities/Graph/Convert-JsonToGraph.ps1"
. "$PSScriptRoot/Utilities/Graph/Resolve-PathGraph.ps1"
. "$PSScriptRoot/Utilities/Graph/Resolve-PathGraphCondenserAdapter.ps1"
. "$PSScriptRoot/Utilities/Graph/Resolve-PathGraphTokenAdapter.ps1"
. "$PSScriptRoot/Utilities/Graph/Resolve-PathGraphForConduction.ps1"
. "$PSScriptRoot/Utilities/Graph/Resolve-ModulePathSignal.ps1"
. "$PSScriptRoot/Utilities/Graph/Resolve-PathGraphForPublisher.ps1"
. "$PSScriptRoot/Utilities/IO/LocalFileSystem/Read-JsonFileAsSignal.ps1"
. "$PSScriptRoot/Utilities/IO/LocalFileSystem/Wait-ForFileUnlock.ps1"
. "$PSScriptRoot/Utilities/Json/Convert-JsonToHashtable.ps1"
. "$PSScriptRoot/Utilities/Json/Get-DictionaryValue.ps1"
. "$PSScriptRoot/Utilities/Json/Get-JsonObjectFromFile.ps1"
. "$PSScriptRoot/Utilities/Json/Get-VirtualValueFromJson.ps1"
. "$PSScriptRoot/Utilities/Json/Resolve-FilteredArrayItem.ps1"
. "$PSScriptRoot/Utilities/Json/Resolve-PathFromDictionaryNoSignal.ps1"
. "$PSScriptRoot/Utilities/Json/Resolve-RegexPlaceholders.ps1"
. "$PSScriptRoot/Utilities/Json/Set-DictionaryValue.ps1"
. "$PSScriptRoot/Utilities/Json/Test-Paths.ps1"
. "$PSScriptRoot/Utilities/Tooling/Resolve-DotNetLibraryFromNuget.ps1"
. "$PSScriptRoot/Utilities/Tooling/Invoke-EvaluateAgainstDoctrine.ps1"
. "$PSScriptRoot/Utilities/Tooling/Invoke-TestGraph.ps1"
. "$PSScriptRoot/Utilities/Tooling/Invoke-TraceSignalTree.ps1"
. "$PSScriptRoot/Utilities/Tooling/Invoke-VisualizeSignalTreeTrace.ps1"
. "$PSScriptRoot/Utilities/Tooling/SovereignTrust.Foundation.Diagrams.ps1"
. "$PSScriptRoot/Utilities/Tooling/Test-IsClassDefined.ps1"


# Export public utility functions
Export-ModuleMember -Function Invoke-ST
Export-ModuleMember -Function Initialize-STEnvironment

Export-ModuleMember -Function Resolve-ClonePlan
Export-ModuleMember -Function Invoke-PlanIterationWorker
Export-ModuleMember -Function Invoke-STRunspacePool

# Previous set of public exports
Export-ModuleMember -Function Resolve-Conduit
Export-ModuleMember -Function Invoke-FabCondenser
Export-ModuleMember -Function Invoke-HydrationCondenser
Export-ModuleMember -Function Invoke-TokenCondenser

Export-ModuleMember -Function Invoke-MappedAdapter
Export-ModuleMember -Function Invoke-CondenserAdapter


# TODO: Don't Export internal functions, only export wrappers and their subsequent invoker.
#Export-ModuleMember -Function Invoke-FabricateAdapter

Export-ModuleMember -Function Invoke-CloneItem
Export-ModuleMember -Function New-MappedCondenserAdapterFromGraph
Export-ModuleMember -Function New-AdapterRegistration
Export-ModuleMember -Function Register-AdapterToMappedSlot
Export-ModuleMember -Function Register-MappedAdapter
Export-ModuleMember -Function Register-ModuleLoaded
Export-ModuleMember -Function Resolve-AdaptersFromJacket
Export-ModuleMember -Function Resolve-RegisteredAdapter
Export-ModuleMember -Function Resolve-MappedAdapter
Export-ModuleMember -Function Resolve-ConductorAdapters
Export-ModuleMember -Function Resolve-DependencyModuleFromGraph
Export-ModuleMember -Function Test-ModuleLoaded
Export-ModuleMember -Function Invoke-GridCondenser
Export-ModuleMember -Function Invoke-JsonTokenCondenser
Export-ModuleMember -Function Invoke-GraphCondenser
Export-ModuleMember -Function Invoke-ConductionCondenser
Export-ModuleMember -Function Invoke-GraphConductionCondenser
Export-ModuleMember -Function Invoke-Graph
##Export-ModuleMember -Function Apply-HydrationToGraph
Export-ModuleMember -Function Convert-VirtualPathToWirePath
##Export-ModuleMember -Function Ensure-HydrationIntentInSignal
Export-ModuleMember -Function Invoke-GraphHydrationCondenser
#Export-ModuleMember -Function Invoke-ApplyHydrationCondenser
Export-ModuleMember -Function Invoke-GlobalCondenser
#Export-ModuleMember -Function Read-HydrationFile
Export-ModuleMember -Function Resolve-GraphHydrationQueue
Export-ModuleMember -Function Resolve-HydrationSourcePath
Export-ModuleMember -Function Invoke-HotPathResolution
Export-ModuleMember -Function Invoke-MemoryCondenser
Export-ModuleMember -Function Invoke-PathHydration
Export-ModuleMember -Function Merge-CondenserCore
Export-ModuleMember -Function Complete-Conduction
##Export-ModuleMember -Function ConductionCoreFunctions
##Export-ModuleMember -Function ConductionPhaseFunctions
Export-ModuleMember -Function Convert-AgentAdaptersToConductor
Export-ModuleMember -Function Get-AgentForConductor
Export-ModuleMember -Function Invoke-Conduction
Export-ModuleMember -Function Resolve-RelativePathFromWirePath-na
Export-ModuleMember -Function Start-Conduction
Export-ModuleMember -Function Start-BondingConduction
Export-ModuleMember -Function Resolve-Conductor
Export-ModuleMember -Function Start-SovereignTrust
Export-ModuleMember -Function Convert-GraphToJson
Export-ModuleMember -Function Convert-JsonToGraph
Export-ModuleMember -Function Resolve-PathGraph
Export-ModuleMember -Function Resolve-PathGraphCondenserAdapter
Export-ModuleMember -Function Resolve-PathGraphForConduction
Export-ModuleMember -Function Resolve-ModulePathSignal
Export-ModuleMember -Function Resolve-PathGraphForPublisher
Export-ModuleMember -Function Read-JsonFileAsSignal
Export-ModuleMember -Function Wait-ForFileUnlock
Export-ModuleMember -Function Convert-JsonToHashtable
Export-ModuleMember -Function Get-DictionaryValue
Export-ModuleMember -Function Get-JsonObjectFromFile
Export-ModuleMember -Function Get-VirtualValueFromJson
Export-ModuleMember -Function Resolve-FilteredArrayItem
Export-ModuleMember -Function Resolve-PathFromDictionaryNoSignal
Export-ModuleMember -Function Resolve-RegexPlaceholders
Export-ModuleMember -Function Set-DictionaryValue
Export-ModuleMember -Function Test-Paths
Export-ModuleMember -Function Resolve-DotNetLibraryFromNuget
Export-ModuleMember -Function Invoke-EvaluateAgainstDoctrine
Export-ModuleMember -Function Invoke-TestGraph
Export-ModuleMember -Function Invoke-TraceSignalTree
Export-ModuleMember -Function Invoke-VisualizeSignalTreeTrace
#Export-ModuleMember -Function SovereignTrust.Foundation.Diagrams
Export-ModuleMember -Function Test-IsClassDefined
Export-ModuleMember -Function New-Conductor
Export-ModuleMember -Function Invoke-HydrateTokenCondenser
#        $bondingConductor = New-Conductor -HostConductor $null

Export-ModuleMember -Function Invoke-MappedStorageAdapter
Export-ModuleMember -Function Invoke-NetworkAdapter
Export-ModuleMember -Function Invoke-TokenStorage
Export-ModuleMember -Function Invoke-MappedAdapter
Export-ModuleMember -Function Start-SignalWrapper
#Export-ModuleMember -Function Invoke-LogMessage
#Export-ModuleMember -Function Invoke-LogInformation
#Export-ModuleMember -Function Invoke-LogWarning
#Export-ModuleMember -Function Invoke-LogCritical
Export-ModuleMember -Function Invoke-Telemetry

