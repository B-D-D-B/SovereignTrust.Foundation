<#
Class: SignalCondenser
Purpose: Write bounded Signal entries and assert native string values in ST plans.
Activities: Log, Assert
Failure: Critical Signal without Result; existing mapped/phase propagation applies.
#>
class SignalCondenser {
    [Signal]$Signal

    static [SignalCondenser] Start([MappedCondenserAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [SignalCondenser]::new()
        $instance.Signal = [Signal]::Start('SignalCondenser.Control') | Select-Object -Last 1
        return $instance
    }

    hidden [object] ReadMember([object]$source, [string]$name) {
        if ($null -eq $source) { return [pscustomobject]@{ Found = $false; Value = $null } }
        if ($source -is [System.Collections.IDictionary]) {
            if (-not $source.Contains($name)) { return [pscustomobject]@{ Found = $false; Value = $null } }
            return [pscustomobject]@{ Found = $true; Value = $source[$name] }
        }
        if ($source -is [System.Collections.IEnumerable] -and $source -isnot [string]) {
            return [pscustomobject]@{ Found = $false; Value = $null }
        }
        $property = $source.PSObject.Properties[$name]
        if ($null -eq $property) { return [pscustomobject]@{ Found = $false; Value = $null } }
        return [pscustomobject]@{ Found = $true; Value = $property.Value }
    }

    hidden [object] ReadPath([Signal]$itemSignal, [string]$path) {
        if (-not $this.ValidPath($path)) {
            return [pscustomobject]@{ Found = $false; Value = $null }
        }
        $current = [object]$itemSignal
        foreach ($segment in $path.Split('.')) {
            if ($segment -cnotmatch '^(?:[A-Za-z_][A-Za-z0-9_]*|[*#@%~])\z') {
                return [pscustomobject]@{ Found = $false; Value = $null }
            }
            $member = switch -CaseSensitive ($segment) {
                '*' { 'Pointer' }
                '#' { 'Grid' }
                '@' { 'Result' }
                '%' { 'Jacket' }
                '~' { 'Control' }
                default { $segment }
            }
            $read = $this.ReadMember($current, $member)
            if (-not $read.Found) { return [pscustomobject]@{ Found = $false; Value = $null } }
            $current = $read.Value
            if ($null -eq $current) { return [pscustomobject]@{ Found = $false; Value = $null } }
        }
        return [pscustomobject]@{ Found = $true; Value = $current }
    }

    hidden [bool] ValidText([object]$value, [int]$limit) {
        return $value -is [string] -and -not [string]::IsNullOrWhiteSpace($value) -and $value.Length -le $limit
    }

    hidden [bool] ValidPath([object]$path) {
        return $path -is [string] -and $path.Length -le 512 -and
            $path -cmatch '^(?:[A-Za-z_][A-Za-z0-9_]*|[*#@%~])(?:\.(?:[A-Za-z_][A-Za-z0-9_]*|[*#@%~]))*\z'
    }

    [Signal] Invoke([string]$Slot, [string]$Activity, [Signal]$ConductionSignal, [object]$Plan, [Signal]$ItemSignal) {
        $opSignal = [Signal]::Start('SignalCondenser.Invoke', $ItemSignal) | Select-Object -Last 1
        if ($Activity -cnotin @('Log', 'Assert')) {
            $null = $opSignal.LogCritical('Unsupported SignalCondenser activity.')
            return $opSignal
        }
        try {
            $configRead = $this.ReadMember($Plan, 'Config')
            if (-not $configRead.Found -or $null -eq $configRead.Value) { throw 'config' }
            $config = $configRead.Value
            $messageRead = $this.ReadMember($config, 'Message')

            if ($Activity -ceq 'Log') {
                $levelRead = $this.ReadMember($config, 'Level')
                $pathRead = $this.ReadMember($config, 'MessagePath')
                $expectedRead = $this.ReadMember($config, 'Expected')
                if ($expectedRead.Found) { throw 'expected' }
                if (-not $levelRead.Found -or $levelRead.Value -isnot [string] -or
                    $levelRead.Value -cnotin @('Information', 'Warning', 'Critical')) { throw 'level' }
                if ($messageRead.Found -eq $pathRead.Found) { throw 'origin' }
                if ($pathRead.Found) {
                    if (-not $this.ValidPath($pathRead.Value)) { throw 'path' }
                    $valueRead = $this.ReadPath($ItemSignal, $pathRead.Value)
                    if (-not $valueRead.Found) { throw 'path' }
                    $message = $valueRead.Value
                }
                else { $message = $messageRead.Value }
                if (-not $this.ValidText($message, 2048)) { throw 'message' }
                $null = $opSignal.LogMessage($levelRead.Value, $message)
                if ($levelRead.Value -ceq 'Critical') { return $opSignal }
                $opSignal.SetResult([pscustomobject]@{ Activity = 'Log'; Passed = $true; Level = $levelRead.Value })
                return $opSignal
            }

            $pathRead = $this.ReadMember($config, 'ValuePath')
            $predicateRead = $this.ReadMember($config, 'Predicate')
            $expectedRead = $this.ReadMember($config, 'Expected')
            if (-not $pathRead.Found -or -not $this.ValidPath($pathRead.Value)) { throw 'path' }
            if (-not $predicateRead.Found -or $predicateRead.Value -isnot [string] -or
                $predicateRead.Value -cnotin @('IsString', 'IsNonBlankString', 'EqualsString')) { throw 'predicate' }
            if (-not $this.ValidText($messageRead.Value, 2048)) { throw 'message' }
            if ($predicateRead.Value -ceq 'EqualsString') {
                if (-not $expectedRead.Found -or $expectedRead.Value -isnot [string] -or
                    $expectedRead.Value.Length -gt 2048) { throw 'expected' }
            }
            elseif ($expectedRead.Found) { throw 'expected' }

            $valueRead = $this.ReadPath($ItemSignal, $pathRead.Value)
            $passed = $valueRead.Found -and $valueRead.Value -is [string]
            if ($passed) {
                switch -CaseSensitive ($predicateRead.Value) {
                    'IsNonBlankString' { $passed = -not [string]::IsNullOrWhiteSpace($valueRead.Value) }
                    'EqualsString' { $passed = [string]::Equals($valueRead.Value, $expectedRead.Value, [System.StringComparison]::Ordinal) }
                }
            }
            if (-not $passed) {
                $suffix = " [Path=$($pathRead.Value); Predicate=$($predicateRead.Value)]"
                $prefixLength = [Math]::Min($messageRead.Value.Length, 2560 - $suffix.Length)
                $null = $opSignal.LogCritical($messageRead.Value.Substring(0, $prefixLength) + $suffix)
                return $opSignal
            }
            $null = $opSignal.LogInformation('Assertion passed.')
            $opSignal.SetResult([pscustomobject]@{ Activity = 'Assert'; Passed = $true; Predicate = $predicateRead.Value })
            return $opSignal
        }
        catch {
            $null = $opSignal.LogCritical('Invalid SignalCondenser configuration or value path.')
            return $opSignal
        }
    }
}
