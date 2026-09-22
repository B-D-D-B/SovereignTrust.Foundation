using module ../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1

$ErrorActionPreference = 'Stop'

class MappedTokenAdapter {
    [hashtable]$Values
    [int]$InvocationCount
    [object]$LastPlan
    [object]$LastSignal
    [object]$LastItemSignal

    MappedTokenAdapter([hashtable]$Values) {
        $this.Values = $Values
    }

    [Signal] Invoke(
        [string]$Slot,
        [string]$Activity,
        [Signal]$ConductionSignal,
        [object]$Plan,
        [Signal]$ItemSignal
    ) {
        $this.InvocationCount++
        $this.LastPlan = $Plan
        $this.LastSignal = $ConductionSignal
        $this.LastItemSignal = $ItemSignal
        $resultSignal = [Signal]::Start("Reference:$($Plan.Path)") | Select-Object -Last 1

        if ($this.Values.ContainsKey([string]$Plan.Path)) {
            $resultSignal.SetResult($this.Values[[string]$Plan.Path])
        }

        return $resultSignal
    }
}

$foundationRoot = Join-Path $PSScriptRoot '../Src/PowerShell'
. "$foundationRoot/Utilities/Adapters/Token/Dynamic/Resolve-TokenDynamic.ps1"
. "$foundationRoot/Utilities/Adapters/Token/Invoke-TokenDynamic.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-TestDynamic(
    [string]$Path,
    [MappedTokenAdapter]$MappedAdapter
) {
    $signal = [Signal]::Start('DynamicTest') | Select-Object -Last 1
    $itemSignal = [Signal]::Start('DynamicTestItem') | Select-Object -Last 1
    $plan = [pscustomobject]@{
        Config = [pscustomobject]@{
            MyArray = @('zero', 'one', 'two')
        }
    }

    return Resolve-TokenDynamic `
        -Path $Path `
        -MappedAdapter $MappedAdapter `
        -Signal $signal `
        -ItemSignal $itemSignal `
        -Plan $plan |
        Select-Object -Last 1
}

$nestedArrays = [object[]]@(
    [object[]]@('a', 'b'),
    [object[]]@('c', 'd')
)

$adapter = [MappedTokenAdapter]::new(@{
    'Memory.Plan.Config.MyArray' = [object[]]@('zero', 'one', 'two')
    'Memory.Plan.Config.MyObject' = [pscustomobject][ordered]@{
        First  = 'A'
        Second = 'B'
    }
    'Memory.Plan.Config.NestedArrays' = $nestedArrays
    'Memory.Plan.Config.Integer' = 7
    'Memory.Plan.Config.NumberText' = '42'
    'Memory.Plan.Config.TrueValue' = $true
    'Memory.Plan.Config.FalseValue' = $false
    'Memory.Plan.Config.DisplayName' = 'Alpha Beta'
    'Memory.Plan.Config.QuotedText' = '"alpha",''beta'''
    'Memory.Plan.Config.CommaText' = 'alpha,beta'
    'Memory.Plan.Config.FilePath' = 'C:\output\image.png'
    'Memory.Plan.Config.JsonText' = '{"Name":"SDA","Count":2}'
    'Memory.Plan.Config.EmptyText' = ''
    'Memory.Plan.Config.TimeText' = '17:30'
    'Memory.Plan.Config.Offset' = '+1h'
    'Memory.Plan.Config.DateText' = '2024-12-01'
    'Memory.Plan.Config.TimeZone' = 'UTC'
})

$indexSignal = Invoke-TestDynamic -Path 'GetIndex([Memory.Plan.Config.MyArray~],1)' -MappedAdapter $adapter
Assert-True (-not $indexSignal.Failure() -and $indexSignal.GetResult() -eq 'one') 'Typed GetIndex did not return index 1.'

$invocationsBeforeCacheTest = $adapter.InvocationCount
$cacheSignal = Invoke-TestDynamic -Path 'In([Memory.Plan.Config.MyArray~],[Memory.Plan.Config.MyArray~])' -MappedAdapter $adapter
Assert-True ($cacheSignal.GetResult() -eq $true) 'Repeated typed references did not preserve their native values.'
Assert-True (($adapter.InvocationCount - $invocationsBeforeCacheTest) -eq 1) 'A repeated typed reference was not cached within its expression.'

$negativeIndexSignal = Invoke-TestDynamic -Path 'GetIndex([Memory.Plan.Config.MyArray~],-1)' -MappedAdapter $adapter
Assert-True ($negativeIndexSignal.GetResult() -eq 'two') 'Typed GetIndex did not support a negative index.'

$legacyIndexSignal = Invoke-TestDynamic -Path 'GetIndex(zero,one,two,1)' -MappedAdapter $adapter
Assert-True ($legacyIndexSignal.GetResult() -eq 'one') 'Legacy GetIndex behavior regressed.'

$typedToArraySignal = Invoke-TestDynamic -Path 'ToArray([Memory.Plan.Config.MyArray~],.)' -MappedAdapter $adapter
Assert-True ((@($typedToArraySignal.GetResult()) -join ',') -eq 'zero,one,two') 'ToArray did not preserve a native array.'

$legacyToArraySignal = Invoke-TestDynamic -Path 'ToArray(zero.one.two,.)' -MappedAdapter $adapter
Assert-True ((@($legacyToArraySignal.GetResult()) -join ',') -eq 'zero,one,two') 'Legacy ToArray behavior regressed.'

$joinSignal = Invoke-TestDynamic -Path 'Join([Memory.Plan.Config.MyArray~],|)' -MappedAdapter $adapter
Assert-True ($joinSignal.GetResult() -eq 'zero|one|two') 'Join did not consume a native array.'

$joinValuesSignal = Invoke-TestDynamic -Path 'JoinValues([Memory.Plan.Config.MyObject~],|)' -MappedAdapter $adapter
Assert-True ($joinValuesSignal.GetResult() -eq 'A|B') 'JoinValues did not consume a native object.'

$joinArraysSignal = Invoke-TestDynamic -Path 'JoinArrays([Memory.Plan.Config.NestedArrays~],-)' -MappedAdapter $adapter
Assert-True ($joinArraysSignal.GetResult() -eq 'ab-cd') 'JoinArrays did not consume nested native arrays.'

$inSignal = Invoke-TestDynamic -Path "In([Memory.Plan.Config.MyArray~],'two,other')" -MappedAdapter $adapter
Assert-True ($inSignal.GetResult() -eq $true) 'In did not consume a native array.'

$notInSignal = Invoke-TestDynamic -Path "NotIn([Memory.Plan.Config.MyArray~],'two,other')" -MappedAdapter $adapter
Assert-True ($notInSignal.GetResult() -eq $false) 'NotIn did not consume a native array.'

$formatSignal = Invoke-TestDynamic -Path 'FormatJsonAsText([Memory.Plan.Config.MyObject~])' -MappedAdapter $adapter
Assert-True ($formatSignal.GetResult() -like '*First: A*') 'FormatJsonAsText did not consume a native object.'

$extensionSignal = Invoke-TestDynamic -Path 'GetFileExtension([Memory.Plan.Config.FilePath~])' -MappedAdapter $adapter
Assert-True ($extensionSignal.GetResult() -eq 'png') 'GetFileExtension did not consume a typed string.'

$initialsSignal = Invoke-TestDynamic -Path 'GetInitials([Memory.Plan.Config.DisplayName~])' -MappedAdapter $adapter
Assert-True ($initialsSignal.GetResult() -eq 'AB') 'GetInitials did not consume a typed string.'

$removeQuotesSignal = Invoke-TestDynamic -Path 'RemoveQuotes([Memory.Plan.Config.QuotedText~])' -MappedAdapter $adapter
Assert-True ($removeQuotesSignal.GetResult() -eq 'alpha,beta') 'RemoveQuotes did not consume a typed string.'

$replaceSignal = Invoke-TestDynamic -Path 'Replace([Memory.Plan.Config.CommaText~],beta,gamma)' -MappedAdapter $adapter
Assert-True ($replaceSignal.GetResult() -eq 'alpha,gamma') 'Replace did not preserve commas in a typed source string.'

Assert-True ((Invoke-TestDynamic -Path 'Gt([Memory.Plan.Config.Integer~],6)' -MappedAdapter $adapter).GetResult()) 'Gt did not consume a typed integer.'
Assert-True ((Invoke-TestDynamic -Path 'Lt([Memory.Plan.Config.Integer~],8)' -MappedAdapter $adapter).GetResult()) 'Lt did not consume a typed integer.'
Assert-True ((Invoke-TestDynamic -Path 'Add([Memory.Plan.Config.Integer~],5)' -MappedAdapter $adapter).GetResult() -eq 12) 'Add did not consume a typed integer.'
Assert-True ((Invoke-TestDynamic -Path 'Subtract([Memory.Plan.Config.Integer~],2)' -MappedAdapter $adapter).GetResult() -eq 5) 'Subtract did not consume a typed integer.'

$ifSignal = Invoke-TestDynamic -Path 'If([Memory.Plan.Config.TrueValue~],[Memory.Plan.Config.MyObject~],no)' -MappedAdapter $adapter
Assert-True ([object]::ReferenceEquals($ifSignal.GetResult(), $adapter.Values['Memory.Plan.Config.MyObject'])) 'If did not preserve the selected native object.'

$substringSignal = Invoke-TestDynamic -Path 'Substring([Memory.Plan.Config.CommaText~],last,4)' -MappedAdapter $adapter
Assert-True ($substringSignal.GetResult() -eq 'beta') 'Substring did not consume a typed string.'

$toIntSignal = Invoke-TestDynamic -Path 'ToInt([Memory.Plan.Config.NumberText~])' -MappedAdapter $adapter
Assert-True ($toIntSignal.GetResult() -is [int] -and $toIntSignal.GetResult() -eq 42) 'ToInt did not return a native integer.'

$toJsonSignal = Invoke-TestDynamic -Path 'ToJson([Memory.Plan.Config.MyObject~])' -MappedAdapter $adapter
$toJsonResult = $toJsonSignal.GetResult() | ConvertFrom-Json
Assert-True ($toJsonResult.First -eq 'A' -and $toJsonResult.Second -eq 'B') 'ToJson did not serialize a native object.'

$fromJsonSignal = Invoke-TestDynamic -Path 'FromJson([Memory.Plan.Config.JsonText~])' -MappedAdapter $adapter
Assert-True ($fromJsonSignal.GetResult().Name -eq 'SDA' -and $fromJsonSignal.GetResult().Count -eq 2) 'FromJson did not deserialize a typed JSON string.'

Assert-True ((Invoke-TestDynamic -Path 'FillDigits([Memory.Plan.Config.Integer~],3)' -MappedAdapter $adapter).GetResult() -eq '007') 'FillDigits did not consume a typed integer.'
Assert-True ((Invoke-TestDynamic -Path 'Not([Memory.Plan.Config.FalseValue~])' -MappedAdapter $adapter).GetResult()) 'Not did not consume a native Boolean.'
Assert-True ((Invoke-TestDynamic -Path 'Equals([Memory.Plan.Config.Integer~],7)' -MappedAdapter $adapter).GetResult()) 'Equals did not consume a typed integer.'
Assert-True ((Invoke-TestDynamic -Path 'NotEquals([Memory.Plan.Config.Integer~],8)' -MappedAdapter $adapter).GetResult()) 'NotEquals did not consume a typed integer.'
Assert-True ((Invoke-TestDynamic -Path 'And([Memory.Plan.Config.TrueValue~],true)' -MappedAdapter $adapter).GetResult()) 'And did not consume a native Boolean.'
Assert-True ((Invoke-TestDynamic -Path 'Or([Memory.Plan.Config.FalseValue~],true)' -MappedAdapter $adapter).GetResult()) 'Or did not consume a native Boolean.'
Assert-True ((Invoke-TestDynamic -Path 'IsNotNull([Memory.Plan.Config.Integer~])' -MappedAdapter $adapter).GetResult()) 'IsNotNull did not consume a typed value.'
Assert-True ((Invoke-TestDynamic -Path 'IsNullOrEmpty([Memory.Plan.Config.EmptyText~])' -MappedAdapter $adapter).GetResult()) 'IsNullOrEmpty did not consume a typed empty string.'
Assert-True (-not (Invoke-TestDynamic -Path 'IsNotNullOrEmpty([Memory.Plan.Config.EmptyText~])' -MappedAdapter $adapter).GetResult()) 'IsNotNullOrEmpty mishandled a typed empty string.'
Assert-True ((Invoke-TestDynamic -Path 'Get12HourTime([Memory.Plan.Config.TimeText~])' -MappedAdapter $adapter).GetResult() -eq '5:30 PM') 'Get12HourTime did not consume a typed time string.'

$utcNowSignal = Invoke-TestDynamic -Path 'UtcNow([Memory.Plan.Config.Offset~])' -MappedAdapter $adapter
Assert-True (-not $utcNowSignal.Failure() -and $utcNowSignal.GetResult() -match 'Z$') 'UtcNow did not consume a typed offset.'

$localToUtcSignal = Invoke-TestDynamic -Path 'LocalToUtc([Memory.Plan.Config.DateText~],[Memory.Plan.Config.TimeText~],[Memory.Plan.Config.TimeZone~])' -MappedAdapter $adapter
Assert-True ($localToUtcSignal.GetResult() -eq '2024-12-01T17:30:00Z') 'LocalToUtc did not consume typed date/time arguments.'

Assert-True ((Invoke-TestDynamic -Path 'Add(2,3)' -MappedAdapter $adapter).GetResult() -eq 5) 'Legacy Add behavior regressed.'
Assert-True ((Invoke-TestDynamic -Path 'If(true,yes,no)' -MappedAdapter $adapter).GetResult() -eq 'yes') 'Legacy If behavior regressed.'
Assert-True ((Invoke-TestDynamic -Path 'Replace(alpha,beta,beta,gamma)' -MappedAdapter $adapter).GetResult() -eq 'alpha,gamma') 'Legacy Replace comma preservation regressed.'
Assert-True ((Invoke-TestDynamic -Path 'Substring(alpha,beta,last,4)' -MappedAdapter $adapter).GetResult() -eq 'beta') 'Legacy Substring comma preservation regressed.'
Assert-True ((Invoke-TestDynamic -Path 'RemoveQuotes("alpha,beta")' -MappedAdapter $adapter).GetResult() -eq 'alpha,beta') 'Legacy RemoveQuotes comma preservation regressed.'
Assert-True ((Invoke-TestDynamic -Path 'IsNotNullOrEmpty(alpha,beta)' -MappedAdapter $adapter).GetResult()) 'Legacy null/empty predicate comma preservation regressed.'
$legacyFromJsonSignal = Invoke-TestDynamic -Path 'FromJson({"Name":"Legacy"})' -MappedAdapter $adapter
Assert-True ($legacyFromJsonSignal.GetResult().Name -eq 'Legacy') 'FromJson did not accept literal JSON.'

$invocationsBeforeQuotedLiteral = $adapter.InvocationCount
$quotedSignal = Invoke-TestDynamic -Path "GetFileExtension('[Memory.Plan.Config.MyArray~]')" -MappedAdapter $adapter
Assert-True (-not $quotedSignal.Failure()) 'A quoted reference marker was not treated as literal text.'
Assert-True ($adapter.InvocationCount -eq $invocationsBeforeQuotedLiteral) 'A quoted reference marker triggered graph resolution.'

$embeddedSignal = Invoke-TestDynamic -Path 'GetIndex(prefix-[Memory.Plan.Config.MyArray~],1)' -MappedAdapter $adapter
Assert-True ($embeddedSignal.Failure()) 'An embedded typed reference was not rejected.'

$missingSignal = Invoke-TestDynamic -Path 'GetIndex([Memory.Plan.Config.Missing~],0)' -MappedAdapter $adapter
Assert-True ($missingSignal.Failure()) 'A missing typed reference did not fail.'

$forwardedSignal = [Signal]::Start('ForwardedSignal') | Select-Object -Last 1
$forwardedItemSignal = [Signal]::Start('ForwardedItemSignal') | Select-Object -Last 1
$forwardedPlan = [pscustomobject]@{
    Path = 'Dynamic.GetIndex([Memory.Plan.Config.MyArray~],2)'
    Config = [pscustomobject]@{ Marker = 'ForwardedConfig' }
}
$invokeSignal = Invoke-TokenDynamic `
    -MappedAdapter $adapter `
    -Signal $forwardedSignal `
    -ItemSignal $forwardedItemSignal `
    -Plan $forwardedPlan |
    Select-Object -Last 1

Assert-True ($invokeSignal.GetResult() -eq 'two') 'Invoke-TokenDynamic did not forward reference resolution to Resolve-TokenDynamic.'
Assert-True ([object]::ReferenceEquals($adapter.LastSignal, $forwardedSignal)) 'The conduction signal was not forwarded to the mapped adapter.'
Assert-True ([object]::ReferenceEquals($adapter.LastItemSignal, $forwardedItemSignal)) 'The item signal was not forwarded to the mapped adapter.'
Assert-True ([object]::ReferenceEquals($adapter.LastPlan.Config, $forwardedPlan.Config)) 'The current plan config was not forwarded to the reference plan.'

$missingInvokePlan = [pscustomobject]@{
    Path = 'Dynamic.GetIndex([Memory.Plan.Config.Missing~],0)'
    Config = $forwardedPlan.Config
}
$missingInvokeSignal = Invoke-TokenDynamic `
    -MappedAdapter $adapter `
    -Signal $forwardedSignal `
    -ItemSignal $forwardedItemSignal `
    -Plan $missingInvokePlan |
    Select-Object -Last 1
Assert-True ($missingInvokeSignal.Failure()) 'Invoke-TokenDynamic did not propagate a typed-reference resolution failure.'

$standardPattern = '(?s)\[((?>[^\[\]/]|(?<open>\[)|(?<-open>\]))+(?(open)(?!)))\/\]'
$deferredPattern = '(?s)\[((?>[^\[\]|]|(?<open>\[)|(?<-open>\]))+(?(open)(?!)))\|\]'
$bareReference = '[Memory.Plan.Config.MyArray~]'
$standardExpression = '[Dynamic.GetIndex([Memory.Plan.Config.MyArray~],1)/]'
$deferredExpression = '[Dynamic.GetIndex([Memory.Plan.Config.MyArray~],1)|]'

Assert-True (-not [regex]::IsMatch($bareReference, $standardPattern)) 'Standard hydration matched a bare typed reference.'
Assert-True (-not [regex]::IsMatch($bareReference, $deferredPattern)) 'Deferred hydration matched a bare typed reference.'
Assert-True ([regex]::Matches($standardExpression, $standardPattern).Count -eq 1) 'Standard hydration did not match the enclosing Dynamic expression.'
Assert-True ([regex]::Matches($deferredExpression, $deferredPattern).Count -eq 1) 'Deferred hydration did not match the enclosing Dynamic expression.'

Write-Output 'PASS: typed Dynamic references, native collections, legacy compatibility, and hydration boundaries.'
