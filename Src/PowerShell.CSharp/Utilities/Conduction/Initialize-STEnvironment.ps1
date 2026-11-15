function Initialize-STEnvironment {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Environment,[SignalGraph.Signal]$ParentSignal)
    $ErrorActionPreference='Stop'
    $operation=[SignalGraph.Signal]::Start('Initialize-STEnvironment',$ParentSignal)
    try {
    $definition=ConvertFrom-Json ([SovereignTrust.Foundation.Utilities.Conduction.EnvironmentInitializer]::CloneEnvironmentJson((ConvertTo-Json -InputObject $Environment -Depth 100))) -Depth 100
    $types=@{
        FabCondenser=[FabCondenser];RestCondenser=[RestCondenser];ProcessCondenser=[ProcessCondenser];FormatCondenser=[FormatCondenser];MergeCondenser=[MergeCondenser];MapCondenser=[MapCondenser];TokenCondenser=[TokenCondenser];PlanCondenser=[PlanCondenser];SignalCondenser=[SignalCondenser];HydrationCondenser=[HydrationCondenser];TransformCondenser=[TransformCondenser];ConduitCondenser=[ConduitCondenser];MemoryCondenser=[MemoryCondenser];GraphCondenser=[GraphCondenser];ConductionCondenser=[ConductionCondenser]
        Token_Dynamic=[Token_Dynamic];Token_System=[Token_System];Token_Memory=[Token_Memory];Token_Storage=[Token_Storage];Token_Environment=[Token_Environment];Token_Navigator=[Token_Navigator];Token_Formatter=[Token_Formatter];Token_Conduction=[Token_Conduction];Token_Generator=[Token_Generator];Storage_EmbeddedFileSystem=[Storage_EmbeddedFileSystem]
    }
    $runtimeState=@{Value=$null}
    $lookupScript={
        param($name)
        if($types.ContainsKey($name)){return $types[$name]}
        if($null -eq $runtimeState.Value){throw "Selected business type unavailable before runtime bootstrap: $name"}
        $wirePaths=[Collections.Generic.List[string]]::new()
        $adapterRoot=$runtimeState.Value.Conductor.Memory.Grid['Adapters'].GetPointer()
        foreach($familyNode in $adapterRoot.Grid.Values){
            $family=$familyNode.GetResult()
            foreach($node in $family.Graph.Grid.Values){
                $source=$node.GetProperty('FabSourceIdentity')
                if($null -ne $source -and $source.FullType -ceq $name){$wirePaths.Add($source.VirtualPath)}
            }
        }
        $modules=@($wirePaths|ForEach-Object{($_.Split('.')[0..3]) -join '.'}|Select-Object -Unique)
        if($modules.Count -ne 1){throw "Selected native Fab source has no unique module for type: $name"}
        Resolve-STNativeAdapterType -Selection (Get-STWorkerSelection) -WirePath $wirePaths[0] -FullType $name
    }.GetNewClosure()
    $lookup=[Func[string,Type]]$lookupScript
    $invoke=[Func[object,string,string,SignalGraph.Signal,object,SignalGraph.Signal,SignalGraph.Signal]]{
        param($instance,$slot,$activity,$conduction,$plan,$item)
        $before=if($slot -eq 'Hydration'){$item.GetJacketResult($true)}else{$null}
        $result=$instance.Invoke($slot,$activity,$conduction,$plan,$item)|Select-Object -Last 1
        if($slot -eq 'Hydration' -and $env:ST_NATIVE_ABI_TRACE){
            $after=$result.GetResult($true)
            $diagnostic=[ordered]@{Boundary='PSBusinessHydration';Style=$plan.HydrationStyle;Path=$plan.Path;InputType=if($null -ne $before){$before.GetType().FullName}else{$null};AdaptersType=if($null -ne $before.Adapters){$before.Adapters.GetType().FullName}else{$null};OutputType=if($null -ne $after){$after.GetType().FullName}else{$null};Addresses=@($after.Adapters|ForEach-Object Addresses);Failure=$result.Failure()}
            [IO.File]::AppendAllText($env:ST_NATIVE_ABI_TRACE,($diagnostic|ConvertTo-Json -Depth 5 -Compress)+[Environment]::NewLine)
        }
        $result
    }
    $hydrate=[Func[object,object,SignalGraph.Signal]]{
        param($configuration,$context)
        $request=[SignalGraph.Signal]::Start('HydrateNativeConfiguration',$context)
        # Existing PS hydration walks PSCustomObject/Hashtable/Object[] metadata.
        # Preserve canonical opaque references; do not serialize the live graph.
        $null=$request.SetJacketResult((ConvertTo-STBusinessMetadata $configuration))
        $plan=[pscustomobject]@{Path='%.@';HydrationPlan='@';HydrationStyle='Deferred'}
        $result=Invoke-CondenserAdapter -Slot Hydration -Activity Invoke -Signal $context -Plan $plan -ItemSignal $request|Select-Object -Last 1
        if($env:ST_NATIVE_ABI_TRACE){
            $observed=$result.GetResult($true)
            $diagnostic=[ordered]@{Boundary='NativeConfigurationHydration';InputType=$configuration.GetType().FullName;VirtualPath=$configuration.VirtualPath;InputAddresses=@($configuration.Addresses);OutputType=if($null -ne $observed){$observed.GetType().FullName}else{$null};OutputAddresses=@($observed.Addresses);Failure=$result.Failure()}
            [IO.File]::AppendAllText($env:ST_NATIVE_ABI_TRACE,($diagnostic|ConvertTo-Json -Depth 5 -Compress)+[Environment]::NewLine)
        }
        $result
    }
    $metadata=[Func[object,Collections.IDictionary]]{param($value) ConvertTo-STNativeMetadata $value}
    $bootstrapScript={
        param($runtime)
        $runtimeState.Value=$runtime
        Invoke-CondenserAdapter -Slot Memory -Activity Generate -Signal $runtime.BootstrapSignal -Plan $runtime.Environment -ItemSignal $runtime.EnvironmentSignal|Select-Object -Last 1
    }.GetNewClosure()
    $bootstrap=[Func[SovereignTrust.Foundation.Utilities.Conduction.EnvironmentRuntime,SignalGraph.Signal]]$bootstrapScript
    $writePlanMember=[Action[object,string,object]]{param($plan,$name,$value) $null=Add-PathToDictionary -Dictionary $plan -Path $name -Value $value}
    $readPlanMember=[Func[object,string,object]]{param($plan,$name) $resolved=Resolve-PathFromDictionary -Dictionary $plan -Path $name -SignalLevel Information -Default $null|Select-Object -Last 1; $resolved.GetResult()}
    [SovereignTrust.Foundation.Utilities.Conduction.EnvironmentInitializer]::InitializeRuntime($definition,[string]$definition.Config.ContentRootPath,(Get-Module SovereignTrust.Foundation).Name,$lookup,$invoke,$hydrate,$metadata,$bootstrap,$writePlanMember,$readPlanMember,$ParentSignal)
    } catch {
        $null=$operation.LogCritical("Failed to initialize environment: $($_.Exception.Message)",$null,$_.Exception)
        return $operation
    }
}
