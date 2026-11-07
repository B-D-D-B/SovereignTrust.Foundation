param([string]$Mode = 'Echo', [string]$Value = '')
$stdout = [Console]::OpenStandardOutput()
$stderr = [Console]::OpenStandardError()
switch ($Mode) {
    'Echo' { $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value); $stdout.Write($bytes,0,$bytes.Length) }
    'Binary' { $bytes = [byte[]](0,1,0,255); $stdout.Write($bytes,0,$bytes.Length) }
    'Stdin' { [Console]::OpenStandardInput().CopyTo($stdout) }
    'Nonzero' { $bytes = [System.Text.Encoding]::UTF8.GetBytes('diagnostic'); $stderr.Write($bytes,0,$bytes.Length); exit 7 }
    'Flood' { $bytes = [byte[]]::new(32768); $stdout.Write($bytes,0,$bytes.Length) }
    'ErrorFlood' { $bytes = [byte[]]::new(32768); $stderr.Write($bytes,0,$bytes.Length) }
    'Sleep' { Start-Sleep -Seconds 10 }
    'BlockStdin' { Start-Sleep -Seconds 10 }
    'Tree' {
        $child = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile','-Command','Start-Sleep -Seconds 10') -PassThru -WindowStyle Hidden
        [System.IO.File]::WriteAllText($Value,[string]$child.Id)
        Start-Sleep -Seconds 10
    }
}
