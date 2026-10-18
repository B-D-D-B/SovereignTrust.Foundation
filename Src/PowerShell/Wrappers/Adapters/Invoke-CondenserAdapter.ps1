# Opt-in, in-memory trace. Disabled unless the caller supplies an exact source context.
$script:STExecutionTraceState = $null
function Start-STExecutionTrace {
    param([Parameter(Mandatory)][hashtable]$Context)
    if ($null -ne $script:STExecutionTraceState) { throw 'ST_TRACE_ALREADY_ACTIVE' }
    foreach ($key in @('RunId','CaseId','CorrelationId')) {
        if ([string]$Context[$key] -cnotmatch '^[A-Za-z0-9._-]{1,100}$') { throw 'ST_TRACE_BAD_CONTEXT' }
    }
    $script:STExecutionTraceState = @{
        Context=$Context; Rows=[Collections.Generic.List[object]]::new()
        Stack=[Collections.Generic.List[object]]::new(); Counts=@{}; Sequence=0
        Errors=[Collections.Generic.List[string]]::new()
    }
}
function Assert-STExecutionTraceSerial {
    param([bool]$Parallel)
    if ($null -ne $script:STExecutionTraceState -and $Parallel) {
        $script:STExecutionTraceState.Errors.Add('UnsupportedParallelBoundary')
        throw 'ST_TRACE_PARALLEL_UNSUPPORTED'
    }
}
function Get-STExecutionTraceInputHash {
    param([string[]]$Keys)
    $safe=@(foreach($key in $Keys) {
        if($key.Length -gt 128 -or $key -match '[\x00-\x1f]'){throw 'ST_TRACE_UNSAFE_KEY'}
        $key
    })
    $json=ConvertTo-Json -InputObject $safe -Compress
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json)))
}
function Enter-STExecutionTrace {
    param([string]$BoundaryKind,[string]$Name,[string]$Adapter,[string]$Activity,
          [hashtable]$Iteration=$null,[AllowNull()][object]$EffectIdentity=$null)
    $s=$script:STExecutionTraceState
    if($null -eq $s){return $null}
    if($null -ne $EffectIdentity -and ($EffectIdentity -isnot [string] -or [string]::IsNullOrWhiteSpace($EffectIdentity) -or $EffectIdentity.Length -gt 256 -or $EffectIdentity -match '[\x00-\x1f]')){
        throw 'ST_TRACE_UNSAFE_OPTIONAL_ID'
    }
    if($s.Rows.Count -ge 256 -or $s.Stack.Count -ge 48){$s.Errors.Add('TraceLimit');throw 'ST_TRACE_LIMIT'}
    foreach($value in @($BoundaryKind,$Name,$Adapter,$Activity,$EffectIdentity)){
        if($null -ne $value -and ($value.Length -gt 256 -or $value -match '[\x00-\x1f]')){throw 'ST_TRACE_UNSAFE_ID'}
    }
    $parent=if($s.Stack.Count){$s.Stack[$s.Stack.Count-1]}else{$null}
    $prefix=if($null -ne $parent){$parent.LogicalStepId+'/' }else{''}
    $segment=([uri]::EscapeDataString($BoundaryKind))+':'+([uri]::EscapeDataString($Name))
    $base=$prefix+$segment
    if(-not $s.Counts.ContainsKey($base)){$s.Counts[$base]=0};$s.Counts[$base]++
    $id=$base+'['+$s.Counts[$base]+']'
    $phase=if($BoundaryKind -in @('Bootstrap','Phase')){$Name}elseif($parent){$parent.Phase}else{$null}
    $sourceKey=switch($BoundaryKind){
        'Bootstrap'{'Bootstrap'} 'Phase'{'Plan'} 'Step'{if($phase -ceq 'Bootstrap'){'Bootstrap'}else{'Plan'}}
        'Iteration'{'App'} 'PlanIteration'{'Plan'} default{$BoundaryKind}
    }
    if(-not $s.Context.Sources.Contains($sourceKey)){throw 'ST_TRACE_SOURCE_UNBOUND'}
    $source=$s.Context.Sources[$sourceKey]
    $row=[ordered]@{
        RunId=$s.Context.RunId;CaseId=$s.Context.CaseId;CorrelationId=$s.Context.CorrelationId
        LogicalStepId=$id;ParentLogicalStepId=if($parent){$parent.LogicalStepId}else{$null}
        InvocationId=$s.Context.RunId+':'+$id;ParentInvocationId=if($parent){$parent.InvocationId}else{$null}
        SourcePath=$source.Path;SourceSha256=$source.Sha256;StructuralLocation=$source.Location
        Phase=$phase;StepName=if($BoundaryKind -ceq 'Step'){$Name}elseif($parent){$parent.StepName}else{$null}
        BoundaryName=$Name;BoundaryKind=$BoundaryKind;Adapter=$Adapter;Activity=$Activity
        BranchId=$null;BranchOutcome=$null;Disposition='Required'
        IterationTemplateId=$null;IterationIndex=$null;IterationKey=$null;InputSetSha256=$null;Cardinality=$null
        Sequence=(++$s.Sequence);StartedUtc=[DateTime]::UtcNow.ToString('o');EndedUtc=$null;TerminalSequence=$null
        Status='Started';FailureCode=$null;SkipReason=$null;BlockedBy=$null;InputIdentity=$source.Sha256;EffectIdentity=$EffectIdentity
    }
    foreach($key in @('IterationTemplateId','IterationIndex','IterationKey','InputSetSha256','Cardinality')){
        if($null -ne $Iteration -and $Iteration.ContainsKey($key)){$row[$key]=$Iteration[$key]}
        elseif($parent){$row[$key]=$parent[$key]}
    }
    $s.Rows.Add($row);$s.Stack.Add($row)
    return $row.InvocationId
}
function Write-STExecutionTraceDecision {
    param($InvocationId,[string]$BranchId,$Outcome,[string]$Disposition='Required',
          [AllowNull()][object]$SkipReason=$null,[AllowNull()][object]$BlockedBy=$null,$Cardinality=$null)
    $s=$script:STExecutionTraceState
    if($null -eq $s -or $null -eq $InvocationId){return}
    foreach($optionalId in @($SkipReason,$BlockedBy)){
        if($null -ne $optionalId -and ($optionalId -isnot [string] -or [string]::IsNullOrWhiteSpace($optionalId) -or $optionalId.Length -gt 256 -or $optionalId -match '[\x00-\x1f]')){
            throw 'ST_TRACE_UNSAFE_OPTIONAL_ID'
        }
    }
    $row=$s.Stack[$s.Stack.Count-1]
    if($row.InvocationId -cne $InvocationId){throw 'ST_TRACE_DECISION_PARENT'}
    if($Outcome -isnot [bool] -and $null -ne $Outcome){throw 'ST_TRACE_UNSAFE_DECISION'}
    $row.BranchId=$row.LogicalStepId+'/'+$BranchId;$row.BranchOutcome=$Outcome
    $row.Disposition=$Disposition;$row.SkipReason=$SkipReason;$row.BlockedBy=$BlockedBy
    if($null -ne $Cardinality){$row.Cardinality=[int]$Cardinality}
}
function Exit-STExecutionTrace {
    param($InvocationId,$Signal=$null,[bool]$Threw=$false,[string]$Status=$null)
    $s=$script:STExecutionTraceState
    if($null -eq $s -or $null -eq $InvocationId){return}
    if(-not $s.Stack.Count -or $s.Stack[$s.Stack.Count-1].InvocationId -cne $InvocationId){
        $s.Errors.Add('UnbalancedTerminal');throw 'ST_TRACE_TERMINAL_PARENT'
    }
    $row=$s.Stack[$s.Stack.Count-1];$s.Stack.RemoveAt($s.Stack.Count-1)
    if($Threw){$Status='Failed';$row.FailureCode='Thrown'}
    elseif($Status -notin @('Skipped','Blocked','Unknown')){
        if($null -eq $Signal){$Status='Unknown';$row.FailureCode='NoSignal'}
        elseif($Signal.Failure()){$Status='Failed';$row.FailureCode='SignalFailure'}
        else{$Status='Succeeded'}
    }
    $row.Status=$Status;$row.EndedUtc=[DateTime]::UtcNow.ToString('o');$row.TerminalSequence=(++$s.Sequence)
}
function Get-STExecutionTrace {
    $s=$script:STExecutionTraceState
    if($null -eq $s){return $null}
    $rows=@(foreach($row in $s.Rows){
        $copy=[ordered]@{};foreach($key in $row.Keys){$copy[$key]=$row[$key]}
        if($copy.Status -ceq 'Started'){$copy.Status='Unknown';$copy.FailureCode='MissingTerminal'}
        $copy
    })
    return @{SchemaVersion=1;Rows=$rows;Errors=$s.Errors.ToArray();Complete=($s.Stack.Count -eq 0 -and $s.Errors.Count -eq 0)}
}
function Stop-STExecutionTrace { $script:STExecutionTraceState=$null }

function Invoke-CondenserAdapter {
    [CmdletBinding()]
    param (
        [string]$VirtualPath,
        [string]$Slot,
        [string]$Activity,
        [Parameter(Mandatory)][Signal]$Signal,
        [object]$Plan,
        [Parameter(Mandatory)][Signal]$ItemSignal
    )

    $stTrace = Enter-STExecutionTrace -BoundaryKind 'Condenser' -Name ("Condenser."+ $Slot+"/"+$(if($Activity){$Activity}else{'Invoke'})) -Adapter ("Condenser."+ $Slot) -Activity $(if($Activity){$Activity}else{'Invoke'})
    $stThrew=$false
    # ░▒▓█ SIGNAL START █▓▒░
    $opSignal = [Signal]::Start("Invoke-CondenserAdapter", $Signal) | Select-Object -Last 1

    try {
        # ░▒▓█ VALIDATE INPUT █▓▒░
        if ([string]::IsNullOrWhiteSpace($Slot)) {
            $opSignal.LogCritical("Slot is required.")
            return $opSignal
        }
        if ([string]::IsNullOrWhiteSpace($Activity)) {
            $Activity = "Invoke"
            $opSignal.LogWarning("Activity not specified, defaulted to 'Invoke'. Slot: $Slot")
        }
        if ($null -eq $ItemSignal) {
            $opSignal.LogCritical("ItemSignal is required.")
            return $opSignal
        }

        # ░▒▓█ RESOLVE MAPPED CONDENSER ADAPTER █▓▒░
        $adapterPath = "%.*.#.Adapters.*.#.MappedCondenser"

        $conductorSignal = $Signal.GetControl($true)

        $adapterSignal = Resolve-PathFromDictionary `
            -Dictionary $conductorSignal `
            -Path $adapterPath `
            -SignalLevel "Information" `
        | Select-Object -Last 1

        if ($opSignal.MergeSignalAndVerifyFailure(@($adapterSignal))) {
            $opSignal.LogCritical("Failed resolving MappedCondenser at path: $adapterPath")
            return $opSignal
        }

        if (-not $adapterSignal.HasResult()) {
            $opSignal.LogCritical("MappedCondenser resolution returned no result (path: $adapterPath)")
            return $opSignal
        }

        $adapter = $adapterSignal.GetResult($true)
        if ($null -eq $adapter) {
            $opSignal.LogCritical("MappedCondenserAdapter is null after GetResult().")
            return $opSignal
        }

        # ░▒▓█ TELEMETRY (TRACE) █▓▒░
        #$vp = if ([string]::IsNullOrWhiteSpace($VirtualPath)) { "<mapped>" } else { $VirtualPath }
        #$opSignal.LogInformation("🧭 Condenser route: Slot='$Slot' Activity='$Activity' VirtualPath='$vp' AdapterPath='$adapterPath'")

        # ░▒▓█ INVOKE █▓▒░
        $adapterInvokeSignal = $adapter.Invoke($Slot, $Activity, $Signal, $Plan, $ItemSignal) | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure(@($adapterInvokeSignal))) {
            $opSignal.LogCritical("Condenser Adapter invocation failed (Slot='$Slot', Activity='$Activity').")
            return $opSignal
        }

        if ($adapterInvokeSignal.HasResult()) {
            $opSignal.SetResult($adapterInvokeSignal.GetResult())
        }
        return $opSignal
    }
    catch {
        $stThrew=$true
        $opSignal.LogCritical("Exception during Invoke-CondenserAdapter: $($_.Exception.Message)", $null, $_)
        return $opSignal
    }
    finally { Exit-STExecutionTrace $stTrace $opSignal $stThrew }
}
