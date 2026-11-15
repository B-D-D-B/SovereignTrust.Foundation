param([Parameter(Mandatory)][string]$NativePacket,[Parameter(Mandatory)][string]$NativeSha256,[Parameter(Mandatory)][string]$SourcePacket,[Parameter(Mandatory)][string]$SourceSha256,[Parameter(Mandatory)][string]$RunRoot,[string]$CaseOnly)
$ErrorActionPreference='Stop'
if(Test-Path $RunRoot){throw 'Negative-control root must be new'}
foreach($pair in @(@($NativePacket,$NativeSha256),@($SourcePacket,$SourceSha256))){if((Get-FileHash $pair[0]).Hash -ne $pair[1]){throw 'Negative-control input identity mismatch'}}
$native=Get-Content $NativePacket -Raw|ConvertFrom-Json -Depth 40
$source=Get-Content $SourcePacket -Raw|ConvertFrom-Json -Depth 40
$null=[IO.Directory]::CreateDirectory($RunRoot)
$helper=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Src/PowerShell.CSharp/Bootstrap/STFoundationSelection.ps1'))
$script=@'
param($Case,$Packet,$Sha,$Helper,$Legacy,$Receipt,$AlternateAssembly)
$ErrorActionPreference='Stop'
$selection=Get-Content $Packet -Raw|ConvertFrom-Json -Depth 40
try {
    switch($Case){
        'LegacyFamily' {Import-Module $Legacy -ErrorAction Stop}
        'LegacyTypesAfterRemoval' {Import-Module $Legacy -ErrorAction Stop;Remove-Module SignalGraph -ErrorAction Stop}
        'WrongOrigin' {
            foreach($entry in $selection.SignalGraph.Dependencies){if(-not @([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object FullName -CEQ $entry.Identity).Count){[void][Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath($entry.Path)}}
            [void][Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath($AlternateAssembly)
        }
        'NonDefaultContext' {
            foreach($entry in $selection.SignalGraph.Dependencies){if(-not @([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object FullName -CEQ $entry.Identity).Count){[void][Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath($entry.Path)}}
            $context=[Runtime.Loader.AssemblyLoadContext]::new('Wave2Negative',$true)
            [void]$context.LoadFromAssemblyPath($selection.SignalGraph.Assembly.Path)
        }
        'DependencyNonDefaultContext' {
            $context=[Runtime.Loader.AssemblyLoadContext]::new('Wave2DependencyNegative',$true)
            $entry=@($selection.SignalGraph.Dependencies|Where-Object Identity -like 'Microsoft.Extensions.Logging.Abstractions,*')[0]
            [void]$context.LoadFromAssemblyPath($entry.Path)
        }
    }
    . $Helper
    if($Case -ceq 'ResourceAfterFoundation'){
        $validated=Read-STSelectionPacket $Packet $Sha
        $env:ST_FOUNDATION_MANIFEST=$validated.Foundation.Manifest
        $env:ST_FOUNDATION_SELECTION_PACKET=$Packet
        $env:ST_FOUNDATION_SELECTION_SHA256=$Sha
        $env:PSModulePath=Get-STSelectedDiscoveryPath $validated
        Import-STSelectedFoundation $validated
        $entry=@($validated.AdapterModules|Where-Object {@($_.Files|Where-Object Path -NotMatch '\.(ps1|psm1|psd1|dll|exe)$').Count -gt 0 -and $_.EntryPoints.Count -eq 1})[0]
        $member=@($entry.Files|Where-Object Path -NotMatch '\.(ps1|psm1|psd1|dll|exe)$')[0]
        if($null -eq $member){throw 'No selected non-code resource for negative control'}
        $resource=Join-Path $entry.Root $member.Path
        $before=[IO.File]::ReadAllBytes($resource)
        try{
            [IO.File]::WriteAllBytes($resource,($before+[byte]32))
            Assert-STSelectedEntryPoint $validated (Join-Path $entry.Root $entry.EntryPoints[0])
        }finally{[IO.File]::WriteAllBytes($resource,$before)}
    }
    $null=Read-STSelectionPacket $Packet $Sha
    $result=[ordered]@{Rejected=$false;Error='Unexpectedly accepted';FoundationLoaded=@(Get-Module -All SovereignTrust.Foundation).Count}
}catch{$result=[ordered]@{Rejected=$true;Error=$_.Exception.Message;FoundationLoaded=@(Get-Module -All SovereignTrust.Foundation).Count}}
$result|ConvertTo-Json -Depth 6|Set-Content $Receipt -Encoding utf8NoBOM
'@
$child=Join-Path $RunRoot child.ps1;[IO.File]::WriteAllText($child,$script)
$alternate=Join-Path $RunRoot alternate;[void][IO.Directory]::CreateDirectory($alternate)
$alternateAssembly=Join-Path $alternate SignalGraph.dll
Copy-Item -LiteralPath $native.SignalGraph.Assembly.Path -Destination $alternateAssembly
if((Get-FileHash $alternateAssembly).Hash -ne $native.SignalGraph.Assembly.Sha256){throw 'Negative alternate copy drift'}
$tampered=Join-Path $RunRoot tampered-packet.json
$native.Foundation.Files[0].Sha256='0'*64
$native|ConvertTo-Json -Depth 40|Set-Content $tampered -Encoding utf8NoBOM
$external=Get-Content $NativePacket -Raw|ConvertFrom-Json -Depth 40
$external.AdapterModules[0].Files[0].Sha256='0'*64
$externalPath=Join-Path $RunRoot external-tamper.json
$external|ConvertTo-Json -Depth 40|Set-Content $externalPath -Encoding utf8NoBOM
$oldPin=Get-Content $NativePacket -Raw|ConvertFrom-Json -Depth 40
$oldPin.SignalGraph.Assembly.Identity='SignalGraph, Version=2.0.0.0, Culture=neutral, PublicKeyToken=null'
$oldPinPath=Join-Path $RunRoot old-pin.json
$oldPin|ConvertTo-Json -Depth 40|Set-Content $oldPinPath -Encoding utf8NoBOM
$vectors=@(
    @('PacketDigest',$NativePacket,('0'*64),'ST_NATIVE_PACKET: digest mismatch'),
    @('MemberDigest',$tampered,(Get-FileHash $tampered).Hash,'ST_NATIVE_PACKET: source drift'),
    @('LegacyFamily',$NativePacket,$NativeSha256,'ST_NATIVE_TYPE: PowerShell SignalGraph module forbidden'),
    @('LegacyTypesAfterRemoval',$NativePacket,$NativeSha256,'ST_NATIVE_TYPE: legacy SignalGraph family forbidden'),
    @('WrongOrigin',$NativePacket,$NativeSha256,'ST_NATIVE_DEPENDENCY: actual loaded origin/context mismatch'),
    @('NonDefaultContext',$NativePacket,$NativeSha256,'ST_NATIVE_DEPENDENCY: actual loaded origin/context mismatch'),
    @('DependencyNonDefaultContext',$NativePacket,$NativeSha256,'ST_NATIVE_DEPENDENCY: actual loaded origin/context mismatch'),
    @('ExternalMemberDigest',$externalPath,(Get-FileHash $externalPath).Hash,'ST_NATIVE_ADAPTER:'),
    @('OldCanonicalPin',$oldPinPath,(Get-FileHash $oldPinPath).Hash,'ST_NATIVE_PACKET: canonical 3.0 pin required'),
    @('ResourceAfterFoundation',$NativePacket,$NativeSha256,'ST_NATIVE_ADAPTER:')
)
$cases=@(foreach($vector in $vectors){
    if($CaseOnly -and $vector[0] -cne $CaseOnly){continue}
    $receipt=Join-Path $RunRoot "$($vector[0]).json"
    $start=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME pwsh.exe));$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardError=$true;$start.RedirectStandardOutput=$true
    foreach($arg in @('-NoLogo','-NoProfile','-File',$child,$vector[0],$vector[1],$vector[2],$helper,$source.SignalGraph.Manifest,$receipt,$alternateAssembly)){$start.ArgumentList.Add($arg)}
    $process=[Diagnostics.Process]::Start($start);$identity=[ordered]@{ProcessId=$process.Id;StartTimeUtc=$process.StartTime.ToUniversalTime().ToString('o');Arguments=@($start.ArgumentList)}
    try{
        $out=$process.StandardOutput.ReadToEndAsync();$err=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(120000)){
            if($process.Id -ne $identity.ProcessId -or $process.StartTime.ToUniversalTime().ToString('o') -cne $identity.StartTimeUtc){throw 'Negative child ownership drift'}
            $identity.BeforeTerminationVerified=$true;$identity|ConvertTo-Json -Depth 6|Set-Content (Join-Path $RunRoot "$($vector[0])-child.json") -Encoding utf8NoBOM
            $process.Kill($true);$process.WaitForExit();throw 'Negative child timeout'
        }
        [IO.File]::WriteAllText((Join-Path $RunRoot "$($vector[0])-stdout.txt"),$out.GetAwaiter().GetResult());[IO.File]::WriteAllText((Join-Path $RunRoot "$($vector[0])-stderr.txt"),$err.GetAwaiter().GetResult())
        $identity.ExitCode=$process.ExitCode;$identity.Exited=$process.HasExited
        $result=Get-Content $receipt -Raw|ConvertFrom-Json
        $expectedLoaded=if($vector[0] -ceq 'ResourceAfterFoundation'){1}else{0}
        [ordered]@{Id=$vector[0];Pass=($result.Rejected -and $result.FoundationLoaded -eq $expectedLoaded -and $result.Error.StartsWith($vector[3],[StringComparison]::Ordinal));Error=$result.Error;FoundationLoaded=$result.FoundationLoaded}
    }finally{$identity|ConvertTo-Json -Depth 6|Set-Content (Join-Path $RunRoot "$($vector[0])-child.json") -Encoding utf8NoBOM;$process.Dispose()}
})
$report=[ordered]@{PassCount=@($cases|Where-Object Pass).Count;FailCount=@($cases|Where-Object{-not $_.Pass}).Count;SkipCount=0;Total=$cases.Count;Cases=$cases;NativePacketSha256=$NativeSha256;SourcePacketSha256=$SourceSha256;HelperSha256=(Get-FileHash $helper).Hash;AlternateAssemblySha256=(Get-FileHash $alternateAssembly).Hash}
$report|ConvertTo-Json -Depth 8|Set-Content (Join-Path $RunRoot negative-result.json) -Encoding utf8NoBOM
"$($report.PassCount)/$($report.FailCount)/$($report.Total), skip0"
if($report.FailCount){$cases|Where-Object{-not $_.Pass}|ForEach-Object{"$($_.Id): $($_.Error)"};exit 1}
