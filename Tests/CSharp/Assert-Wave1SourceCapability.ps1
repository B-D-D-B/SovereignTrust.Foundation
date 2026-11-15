# Test-only evidence verifier. Historical origins are metadata, never input paths.
function Assert-STWave1SourceCapability {
    param([Parameter(Mandatory)]$Selection,[Parameter(Mandatory)][string]$TestRoot)
    $fixtureRoot=[IO.Path]::GetFullPath((Join-Path $TestRoot 'Fixtures'))
    $path=Join-Path $fixtureRoot 'wave1-ps-graph-json-unsupported.json'
    $digest='04E1168495D59FE263CD5EDC2088F2A2CF9930847C716832220A3D5E24069E2C'
    if((Get-FileHash -LiteralPath $path).Hash -cne $digest){throw 'ST_CAPABILITY_FIXTURE_HASH'}
    $fixture=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -Depth 30
    function Get-DependencyIdentity($Dependency) {
        [ordered]@{Guid=[string]$Dependency.Guid;Version=[string]$Dependency.Version;Files=@($Dependency.Files|ForEach-Object{[ordered]@{Path=$_.Path;Length=$_.Length;Sha256=$_.Sha256}});Directories=@($Dependency.Directories)}|ConvertTo-Json -Depth 20 -Compress
    }
    function Assert-BoundEvidence($Dependency,$Evidence) {
        if($Evidence.Schema -cne 'ST.Wave1.SourceCapability/1' -or $Evidence.FixtureId -cne 'graph.member-pointer-self-jacket-control.cyclic' -or ($Evidence.Labels -join ',') -cne 'graph.roundtrip,graph.cycle.roundtrip' -or $Evidence.Status -cne 'KnownUnsupportedSource'){throw 'ST_CAPABILITY_CONTRACT'}
        if((Get-DependencyIdentity $Dependency) -cne (Get-DependencyIdentity $Evidence.SelectedSignalGraph)){throw 'ST_CAPABILITY_DEPENDENCY'}
        $references=@($Evidence.HistoricalScript)+@($Evidence.HistoricalRuns|ForEach-Object{$_.Files})
        foreach($ref in $references){
            if([IO.Path]::IsPathFullyQualified($ref.Path)){throw 'ST_CAPABILITY_RELATIVE_PATH'}
            $file=[IO.Path]::GetFullPath((Join-Path $fixtureRoot $ref.Path))
            if(-not $file.StartsWith($fixtureRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'ST_CAPABILITY_PATH_ESCAPE'}
            if((Get-Item -LiteralPath $file).Length -ne $ref.Length -or (Get-FileHash -LiteralPath $file).Hash -cne $ref.Sha256){throw 'ST_CAPABILITY_RAW_IDENTITY'}
        }
        foreach($run in $Evidence.HistoricalRuns){
            $files=@{};foreach($ref in $run.Files){$files[[IO.Path]::GetFileName($ref.Path)]=Join-Path $fixtureRoot $ref.Path}
            $raw=Get-Content -LiteralPath $files['semantic-result.json'] -Raw|ConvertFrom-Json -Depth 30
            $first=@($raw.Cases|Where-Object Id -CEQ 'graph.roundtrip');$second=@($raw.Cases|Where-Object Id -CEQ 'graph.cycle.roundtrip')
            if($raw.Count -ne 18 -or $first.Count -ne 1 -or $second.Count -ne 1 -or $first[0].Pass -ne $false -or $second[0].Pass -ne $false -or $first[0].Value.JsonLength -ne 0 -or $second[0].Value.BlockedBy -cne 'graph.roundtrip'){throw 'ST_CAPABILITY_HISTORICAL_OUTCOME'}
            $errorText=[IO.File]::ReadAllText($files['stderr.txt'])
            # Outer child reports the two assertion IDs; the raw first result retains IsTerminal.
            if(-not $errorText.Contains('graph.roundtrip,graph.cycle.roundtrip') -or -not $first[0].Value.Error.Contains('IsTerminal') -or (Get-Item -LiteralPath $files['graph-raw.json']).Length -ne 0){throw 'ST_CAPABILITY_RAW_FAILURE'}
            $origin=Get-Content -LiteralPath $files['loader-provenance.json'] -Raw|ConvertFrom-Json
            if($origin.Root.SignalSource -cne $Evidence.SelectedSignalGraph.Manifest -or $origin.Root.SignalGraphPath -cne (Join-Path $Evidence.SelectedSignalGraph.Root 'SignalGraph.psm1') -or $origin.Root.PacketSha256 -cne $origin.Worker.PacketSha256 -or -not $origin.WorkerDisposed){throw 'ST_CAPABILITY_HISTORICAL_ORIGIN'}
        }
    }
    Assert-BoundEvidence $Selection.SignalGraph $fixture
    if($null -eq [Graph].GetMethod('ToJson',[type[]]@([bool])) -or $null -eq [Graph].GetMethod('FromJson',[type[]]@([string],[bool]))){throw 'ST_CAPABILITY_METHODS_MUST_EXIST'}
    $helperCount=& (Get-Module SignalGraph) {param($Names) @($Names|ForEach-Object{Get-Command -Name $_ -CommandType Function -ErrorAction SilentlyContinue}).Count} $fixture.MissingHelpers
    if($helperCount -ne 0){throw 'ST_CAPABILITY_HELPER_GAP_CHANGED'}
    $wrongDependency=$Selection.SignalGraph|ConvertTo-Json -Depth 25|ConvertFrom-Json -Depth 25;$wrongDependency.Version='unknown'
    $dependencyRejected=$false;try{Assert-BoundEvidence $wrongDependency $fixture}catch{if($_.Exception.Message -cne 'ST_CAPABILITY_DEPENDENCY'){throw};$dependencyRejected=$true}
    $wrongReceipt=$fixture|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30;$wrongReceipt.HistoricalRuns[0].Files[0].Sha256='0'*64
    $receiptRejected=$false;try{Assert-BoundEvidence $Selection.SignalGraph $wrongReceipt}catch{if($_.Exception.Message -cne 'ST_CAPABILITY_RAW_IDENTITY'){throw};$receiptRejected=$true}
    if(-not $dependencyRejected -or -not $receiptRejected){throw 'ST_CAPABILITY_NEGATIVE_CONTROL'}
    [pscustomobject]@{FixtureId=$fixture.FixtureId;Labels=$fixture.Labels;ManifestSha256=$digest;HistoricalReceipts=@($fixture.HistoricalRuns|ForEach-Object{$_.Files});SelectedSignalGraphManifest=$Selection.SignalGraph.Manifest;SelectedDependencyContentVerified=$true;HistoricalOriginsInformationalOnly=$true;CuratedFixtureRelativeInputsOnly=$true;MethodsExist=$true;HelpersAbsent=$true;AssertionPass=$true;ClassificationChecks=3;ClassificationFailures=0;WrongDependencyRejected=$dependencyRejected;WrongReceiptDigestRejected=$receiptRejected;CapabilityStatus='KnownUnsupportedSource';CapabilityPass=$null}
}
