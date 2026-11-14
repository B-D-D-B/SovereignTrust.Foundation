param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath("$PSScriptRoot/../..")
$catalog=Join-Path $repo 'Src/PowerShell/Classes/Adapters/Catalog'
if(Test-Path -LiteralPath $OutputPath){throw 'ST_CATALOG_OUTPUT: requires absent owned file'}
$waves=@{
    MappedCondenserAdapter=@(2,6);FabCondenser=@(2,6)
    FormatCondenser=@(3);HydrationCondenser=@(3);MapCondenser=@(3);MergeCondenser=@(3);TokenCondenser=@(3);TransformCondenser=@(3);SignalCondenser=@(3);MappedTokenAdapter=@(3,7)
    MemoryCondenser=@(4,5,6);PlanCondenser=@(4,5,6)
    MappedConductionAdapter=@(2,4,6);ConductionCondenser=@(2,4,6);MappedConduitAdapter=@(2,4,6);ConduitCondenser=@(2,4,6);GraphCondenser=@(2,4,6)
    ProcessCondenser=@(5);RestCondenser=@(5);MappedStorageAdapter=@(4,7)
    MappedSessionAdapter=@(6,7);MappedDataAdapter=@(6,7);MappedIntelligenceAdapter=@(6,7);MappedNetworkAdapter=@(6,7);MappedUtilityAdapter=@(6,7);MappedQueueAdapter=@(6,7);MappedSatelliteAdapter=@(6,7);MappedQuantumAdapter=@(6)
}
$special=@{
    'MemoryCondenser.Persist'='Reserved/no persistence implementation'
    'PlanCondenser.InvokePlan'='Reserved/no plan invocation implementation'
    'MappedQueueAdapter.DeferItem'='Incomplete/reserved'
    'MappedSatelliteAdapter.EmitSignalFull'='Incomplete'
    'MappedDataAdapter.WriteBatch'='Unsupported legacy path'
    'MappedTokenAdapter.Get'='Catalog Get differs from source-accepted Read; not uniform support'
}
$index=Get-Content (Join-Path $catalog 'index.json') -Raw|ConvertFrom-Json
$primaryFiles=@(@($index.mappedAdapters)+@($index.condensers)|Where-Object {$_.file}|ForEach-Object{Get-Item (Join-Path $catalog $_.file)})
$owners=@(foreach($file in $primaryFiles|Sort-Object FullName){
    $data=Get-Content $file.FullName -Raw|ConvertFrom-Json -Depth 60
    $name=$data.name
    if(-not $waves.ContainsKey($name)){throw "ST_CATALOG_OWNER: $name"}
    $primary=if($name.StartsWith('Mapped')){"Src/PowerShell/Classes/Adapters/$name.ps1"}else{"Src/PowerShell/Classes/Adapters/Condenser/$name.ps1"}
    if(-not(Test-Path (Join-Path $repo $primary))){throw "ST_CATALOG_SOURCE: $primary"}
    $domain=($name -replace '^Mapped','' -replace 'Condenser$','' -replace 'Adapter$','')
    $helperRoots=@("Src/PowerShell/Utilities/Adapters/$domain","Src/PowerShell/Utilities/Adapters/Condenser/$domain")
    $helpers=@($helperRoots|Where-Object{Test-Path (Join-Path $repo $_)}|ForEach-Object{Get-ChildItem (Join-Path $repo $_) -File -Recurse}|ForEach-Object{[IO.Path]::GetRelativePath($repo,$_.FullName).Replace('\','/')})
    $contract=[IO.Path]::GetFullPath((Join-Path $file.DirectoryName $data.resultContractRef.file))
    if(-not(Test-Path $contract)){throw "ST_CATALOG_CONTRACT: $name"}
    $activities=@(foreach($a in $data.activities){
        $key="$name.$($a.name)"
        [ordered]@{CaseId="catalog.$key";Activity=$a.name;ImplementationStatus='Unimplemented in CSharp; assigned future wave';AssignedWaves=$waves[$name];Disposition=if($special.ContainsKey($key)){$special[$key]}else{'Source-supported behavior to characterize in assigned wave'};ResultFields=$a.result;SourceResultNotes=$a.resultNotes}
    })
    [ordered]@{Owner=$name;Catalog=[IO.Path]::GetRelativePath($repo,$file.FullName).Replace('\','/');CatalogSha256=(Get-FileHash $file.FullName).Hash;PrimarySource=$primary;PrimarySourceSha256=(Get-FileHash (Join-Path $repo $primary)).Hash;Helpers=$helpers;ResultContract=[IO.Path]::GetRelativePath($repo,$contract).Replace('\','/');ResultContractSha256=(Get-FileHash $contract).Hash;AssignedWaves=$waves[$name];Activities=$activities;EmptyInventoryCase=if($activities.Count -eq 0){"catalog.$name.empty"}else{$null}}
})
$activityCount=($owners|ForEach-Object{$_.Activities.Count}|Measure-Object -Sum).Sum
if($owners.Count -ne 28 -or $activityCount -ne 103){throw "ST_CATALOG_DENOMINATOR: $($owners.Count)/$activityCount"}
$ids=@($owners.Activities.CaseId)
if(@($ids|Sort-Object -Unique).Count -ne 103){throw 'ST_CATALOG_DUPLICATE'}
foreach($key in $special.Keys){if("catalog.$key" -notin $ids){throw "ST_CATALOG_SPECIAL: $key"}}
foreach($empty in 'MappedConduitAdapter','MappedQuantumAdapter'){if(@($owners|Where-Object Owner -EQ $empty).Activities.Count -ne 0){throw "ST_CATALOG_EMPTY: $empty"}}
$receipt=[ordered]@{Scope='Wave1 source-bound inventory accounting; no operation implementation pass claimed';OwnerCount=$owners.Count;ActivityCount=$activityCount;Owners=$owners;SourceOnlyRoutes=@('GraphCondenser two-argument Invoke','MappedConduitAdapter two-argument Invoke','MappedQuantumAdapter.SubmitQuantumJob');ExternalPrerequisites=@('Storage_LocalFileSystem lacks mapped five-argument Invoke; no universal local provider claim');Pass=$true}
$stream=[IO.File]::Open($OutputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($receipt|ConvertTo-Json -Depth 40));$stream.Write($bytes)}finally{$stream.Dispose()}
"CATALOG PASS owners=$($owners.Count) activities=$activityCount"
