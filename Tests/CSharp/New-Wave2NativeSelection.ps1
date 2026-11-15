param([Parameter(Mandatory)][string]$NativeDirectory,[Parameter(Mandatory)][string]$OutputPath,[string]$CoreAssembly,[switch]$IncludeDevelopmentAdapters)
$ErrorActionPreference='Stop'
if(Test-Path $OutputPath){throw 'Native selection output must be new'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Src/PowerShell.CSharp'))
function AssemblyEntry($Path){$file=Get-Item -LiteralPath $Path;[ordered]@{Path=$file.FullName;Length=$file.Length;Sha256=(Get-FileHash $file.FullName).Hash;Identity=[Reflection.AssemblyName]::GetAssemblyName($file.FullName).FullName}}
$packet=[ordered]@{Schema='ST.Foundation.NativeSelection/2';Foundation=[ordered]@{Root=$root;Manifest=(Join-Path $root 'SovereignTrust.Foundation.psd1');Files=@(Get-ChildItem $root -Recurse -File -Force|Sort-Object FullName|ForEach-Object{[ordered]@{Path=[IO.Path]::GetRelativePath($root,$_.FullName).Replace('\','/');Length=$_.Length;Sha256=(Get-FileHash $_.FullName).Hash}});Directories=@(Get-ChildItem $root -Recurse -Directory -Force|ForEach-Object{[IO.Path]::GetRelativePath($root,$_.FullName).Replace('\','/')}|Sort-Object)};SignalGraph=[ordered]@{Backend='Native';Assembly=(AssemblyEntry (Join-Path $NativeDirectory SignalGraph.dll));Dependencies=@((AssemblyEntry (Join-Path $PSHOME Newtonsoft.Json.dll)),(AssemblyEntry (Join-Path $NativeDirectory Microsoft.Extensions.Logging.Abstractions.dll)))}}
$packet.AdapterModules=@();$packet.AdapterBootstraps=@()
if($IncludeDevelopmentAdapters){
    $siblings=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    foreach($repository in 'SovereignTrust.Adapters','SDAFusion.Adapters'){
        $repo=Join-Path $siblings $repository
        foreach($directory in Get-ChildItem (Join-Path $repo Src) -Recurse -Directory|Where-Object Name -CEQ PowerShell.CSharp){
            $adapterRoot=$directory.FullName
            $packet.AdapterModules+=@([ordered]@{Repository=$repository;Kind=$directory.Parent.Parent.Name;Provider=$directory.Parent.Name;Root=$adapterRoot;EntryPoints=@(Get-ChildItem $adapterRoot -File -Filter *.psd1|ForEach-Object Name);Files=@(Get-ChildItem $adapterRoot -Recurse -File -Force|Sort-Object FullName|ForEach-Object{[ordered]@{Path=[IO.Path]::GetRelativePath($adapterRoot,$_.FullName).Replace('\','/');Length=$_.Length;Sha256=(Get-FileHash $_.FullName).Hash}});Directories=@(Get-ChildItem $adapterRoot -Recurse -Directory -Force|ForEach-Object{[IO.Path]::GetRelativePath($adapterRoot,$_.FullName).Replace('\','/')}|Sort-Object)})
        }
        $bootstrap=Get-Item (Join-Path $repo 'Src/Bootstrap/Initialize-STFoundation.CSharp.ps1')
        $packet.AdapterBootstraps+=@([ordered]@{Path=$bootstrap.FullName;Length=$bootstrap.Length;Sha256=(Get-FileHash $bootstrap.FullName).Hash})
    }
}
if($CoreAssembly){$packet.Foundation.NativeCore=AssemblyEntry $CoreAssembly}
$packet|ConvertTo-Json -Depth 15|Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
Get-FileHash $OutputPath
