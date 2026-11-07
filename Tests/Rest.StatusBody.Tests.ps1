using module ../Src/PowerShell/SovereignTrust.Foundation.psd1

$ErrorActionPreference = 'Stop'
function Assert([bool]$condition,[string]$message) { if (-not $condition) { throw $message } }
Import-Module (Join-Path $PSScriptRoot '../Src/PowerShell/SovereignTrust.Foundation.psd1') -Force
& (Get-Module SovereignTrust.Foundation) {
    $script:requests = @()
    $script:mockStatus = 200
    $script:throwMode = ''
    function Invoke-RestMethod {
        param($Uri,$Method,$Headers,$Body,$ContentType,[switch]$SkipHttpErrorCheck,$StatusCodeVariable,$ResponseHeadersVariable)
        $script:requests += [pscustomobject]@{ Uri=$Uri; Method=$Method; Body=$Body; StatusMode=[bool]$SkipHttpErrorCheck }
        if ($script:throwMode -eq 'generic') { throw 'SENTINEL_SECRET generic transport failure' }
        if ($script:throwMode -eq 'auth') { throw '401 (Unauthorized) SENTINEL_SECRET' }
        if ($script:throwMode -eq 'details') {
            $record = [Management.Automation.ErrorRecord]::new([Exception]::new('Transport failed'), 'MockRestFailure', [Management.Automation.ErrorCategory]::InvalidOperation, $null)
            $record.ErrorDetails = [Management.Automation.ErrorDetails]::new('SENTINEL_SECRET error details')
            throw $record
        }
        if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value $script:mockStatus -Scope 1 }
        if ($ResponseHeadersVariable) { Set-Variable -Name $ResponseHeadersVariable -Value @{} -Scope 1 }
        return [pscustomobject]@{ id='https://vault.vault.azure.net/secrets/sample/version1' }
    }
    $signal = [Signal]::Start('RestStatusBody') | Select-Object -Last 1
    $rest = [RestCondenser]::new()
    $plan = [pscustomobject]@{ Config=[pscustomobject]@{ Uri='https://vault.vault.azure.net/secrets/sample'; Method='Put'; Body='{"value":"synthetic"}'; ReturnHttpStatus=$true } }
    $result = Invoke-RestCondenserCore -RestCondenser $rest -Activity 'Put' -Signal $signal -ItemSignal $signal -Plan $plan | Select-Object -Last 1
    Assert ($result.Success() -and $result.HasResult() -and $result.GetResult().StatusCode -eq 200 -and
        $script:requests.Count -eq 1 -and $script:requests[0].StatusMode -and $script:requests[0].Method -eq 'Put') 'Status-mode body PUT did not expose HTTP 200.'
    $script:mockStatus = 403
    $result = Invoke-RestCondenserCore -RestCondenser $rest -Activity 'Put' -Signal $signal -ItemSignal $signal -Plan $plan | Select-Object -Last 1
    Assert ($result.Success() -and $result.GetResult().StatusCode -eq 403 -and $script:requests.Count -eq 2) 'Status-mode body PUT did not preserve HTTP 403.'
    $plan.Config | Add-Member NoteProperty RedactDiagnostics $true
    $plan.Config | Add-Member NoteProperty SkipBearerToken $true
    foreach ($mode in @('generic','auth','details')) {
        $script:throwMode = $mode
        $failed = Invoke-RestCondenserCore -RestCondenser $rest -Activity 'Put' -Signal $signal -ItemSignal $signal -Plan $plan | Select-Object -Last 1
        $messages = @($failed.Entries.Message) -join '|'
        $serializedDiagnostics = @($failed.Entries | ForEach-Object Message) | ConvertTo-Json -Depth 10 -Compress
        Assert ($failed.Failure() -and -not $failed.HasResult() -and $messages -notmatch 'SENTINEL_SECRET' -and
            $serializedDiagnostics -notmatch 'SENTINEL_SECRET') "REST $mode failure leaked diagnostic sentinel."
    }
    $script:throwMode = 'generic'
    $wrapped = $rest.Invoke('Rest','Put',$signal,$plan,$signal)
    Assert ($wrapped.Failure() -and -not $wrapped.HasResult() -and
        (@($wrapped.Entries.Message) -join '|') -notmatch 'SENTINEL_SECRET') 'RestCondenser merged failed diagnostics.'
}
Write-Output 'PASS: REST status-mode body request envelope.'
