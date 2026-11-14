function Invoke-ProcessCondenserCore {
    param([object]$Plan)

    function Read-RequiredMember([object]$Object, [string]$Name) {
        if ($null -eq $Object) { throw "Missing $Name." }
        if ($Object -is [System.Collections.IDictionary]) {
            if (-not $Object.Contains($Name)) { throw "Missing $Name." }
            return ,$Object[$Name]
        }
        $property = $Object.PSObject.Properties[$Name]
        if ($null -eq $property) { throw "Missing $Name." }
        return ,$property.Value
    }
    $config = Read-RequiredMember $Plan 'Config'
    $executable = Read-RequiredMember $config 'Executable'
    $arguments = Read-RequiredMember $config 'Arguments'
    $timeout = Read-RequiredMember $config 'TimeoutMilliseconds'
    $maxOutput = Read-RequiredMember $config 'MaximumOutputBytes'
    $maxError = Read-RequiredMember $config 'MaximumErrorBytes'
    if ($executable -isnot [string] -or [string]::IsNullOrWhiteSpace($executable) -or -not [System.IO.Path]::IsPathFullyQualified($executable) -or -not [System.IO.File]::Exists($executable)) { throw 'Executable must be an existing absolute application path.' }
    if ($arguments -isnot [array] -or $arguments.Count -gt 256) { throw 'Arguments must be an array of at most 256 strings.' }
    foreach ($argument in $arguments) { if ($argument -isnot [string] -or $argument.Length -gt 8192) { throw 'Argument must be a string of at most 8192 characters.' } }
    foreach ($bound in @(@($timeout,30000,'TimeoutMilliseconds'),@($maxOutput,16777216,'MaximumOutputBytes'),@($maxError,65536,'MaximumErrorBytes'))) {
        if (($bound[0] -isnot [int] -and $bound[0] -isnot [long]) -or $bound[0] -lt 1 -or $bound[0] -gt $bound[1]) { throw "$($bound[2]) is outside the permitted range." }
    }
    $inputProperty = $config.PSObject.Properties['InputBytes']
    $inputBytes = $null
    if ($config -is [System.Collections.IDictionary]) {
        if ($config.Contains('InputBytes')) { $inputBytes = $config['InputBytes'] }
    } elseif ($null -ne $inputProperty) { $inputBytes = $inputProperty.Value }
    if ($null -ne $inputBytes -and ($inputBytes -isnot [byte[]] -or $inputBytes.Length -gt 8388608)) { throw "InputBytes must be a byte array of at most 8388608 bytes (received $($inputBytes.GetType().FullName))." }

    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $executable
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $null -ne $inputBytes
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $arguments) { [void]$start.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    $output = [System.IO.MemoryStream]::new()
    $errors = [System.IO.MemoryStream]::new()
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $started = $false
    $writeTask = $null; $outTask = $null; $errTask = $null
    try {
        if (-not $process.Start()) { throw 'Process did not start.' }
        $started = $true
        if ($null -ne $inputBytes) { $writeTask = $process.StandardInput.BaseStream.WriteAsync($inputBytes,0,$inputBytes.Length) }
        $outBuffer = [byte[]]::new(8192)
        $errBuffer = [byte[]]::new(4096)
        $outTask = $process.StandardOutput.BaseStream.ReadAsync($outBuffer,0,$outBuffer.Length)
        $errTask = $process.StandardError.BaseStream.ReadAsync($errBuffer,0,$errBuffer.Length)
        $deadlineTask = [System.Threading.Tasks.Task]::Delay($timeout)
        while ($null -ne $writeTask -or $null -ne $outTask -or $null -ne $errTask) {
            if ($timer.ElapsedMilliseconds -ge $timeout) { throw 'Process timed out.' }
            $pending = [System.Collections.Generic.List[System.Threading.Tasks.Task]]::new()
            foreach ($task in @($writeTask,$outTask,$errTask)) { if ($null -ne $task) { $pending.Add($task) } }
            $pending.Add($deadlineTask)
            $done = [System.Threading.Tasks.Task]::WhenAny($pending.ToArray()).GetAwaiter().GetResult()
            if ([object]::ReferenceEquals($done,$deadlineTask)) { throw 'Process timed out.' }
            if ($null -ne $writeTask -and [object]::ReferenceEquals($done,$writeTask)) {
                $null = $writeTask.GetAwaiter().GetResult(); $process.StandardInput.Close(); $writeTask = $null
            } elseif ($null -ne $outTask -and [object]::ReferenceEquals($done,$outTask)) {
                $count = $outTask.GetAwaiter().GetResult()
                if ($count -eq 0) { $outTask = $null } else {
                    if ($output.Length + $count -gt $maxOutput) { throw 'Process output exceeded the bound.' }
                    $output.Write($outBuffer,0,$count)
                    $outTask = $process.StandardOutput.BaseStream.ReadAsync($outBuffer,0,$outBuffer.Length)
                }
            } elseif ($null -ne $errTask -and [object]::ReferenceEquals($done,$errTask)) {
                $count = $errTask.GetAwaiter().GetResult()
                if ($count -eq 0) { $errTask = $null } else {
                    if ($errors.Length + $count -gt $maxError) { throw 'Process diagnostics exceeded the bound.' }
                    $errors.Write($errBuffer,0,$count)
                    $errTask = $process.StandardError.BaseStream.ReadAsync($errBuffer,0,$errBuffer.Length)
                }
            }
        }
        $remaining = $timeout - [int]$timer.ElapsedMilliseconds
        if ($remaining -le 0 -or -not $process.WaitForExit($remaining)) { throw 'Process timed out.' }
        return [pscustomobject]@{ ExitCode = [int]$process.ExitCode; StandardOutputBytes = $output.ToArray(); StandardErrorBytes = $errors.ToArray() }
    }
    catch {
        $original = $_.Exception
        if ($started) {
            try {
                if (-not $process.HasExited) { $process.Kill($true) }
                if (-not $process.WaitForExit(2000)) { throw 'child did not exit within 2000 ms' }
                $active = @($writeTask,$outTask,$errTask) | Where-Object { $null -ne $_ }
                if ($active.Count -gt 0) {
                    $completion = [System.Threading.Tasks.Task]::WhenAll([System.Threading.Tasks.Task[]]$active)
                    try { [void]$completion.Wait(2000) } catch { }
                    if (-not $completion.IsCompleted) { throw 'IO did not complete within 2000 ms' }
                }
            } catch { throw [System.Exception]::new("Process cleanup uncertain after $($original.Message): $($_.Exception.Message)",$original) }
        }
        throw
    }
    finally { $timer.Stop(); $output.Dispose(); $errors.Dispose(); $process.Dispose() }
}
