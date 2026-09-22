function Resolve-TokenDynamic {
    [CmdletBinding()]
    param(
        # Parent signal for lineage
        [Parameter(Mandatory = $false)]
        [Signal]$Signal,

        [Parameter(Mandatory = $false)]
        [Signal]$ItemSignal,

        [Parameter(Mandatory = $false)]
        [MappedTokenAdapter]$MappedAdapter,

        [Parameter(Mandatory = $false)]
        [object]$Plan,

        # Dictionary used by coalesce(...) when it calls Resolve-PathFromDictionary
        [Parameter(Mandatory = $false)]
        [psobject]$Dictionary,

        # Dynamic expression, must start with ::   (e.g. ::utcNow(+1h))
        [Parameter(Mandatory)]
        [string]$Path
    )

    $opSignal = [Signal]::Start("Resolve-TokenDynamic", $Signal) | Select-Object -Last 1
    function Convert-LocalDateTimeToUtc {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Date,          # "2024-12-01" or "12/01/2024"

            [Parameter(Mandatory)]
            [string]$LocalTime,     # "17:00:00"

            [Parameter(Mandatory)]
            [string]$TimeZoneId     # "Australia/Lord_Howe"
        )

        $culture = [System.Globalization.CultureInfo]::InvariantCulture

        # Clean inputs
        $cleanDate = ($Date ?? '').Trim().Trim('"', "'")
        $cleanTime = ($LocalTime ?? '').Trim().Trim('"', "'")

        # Normalize whitespace
        $cleanDate = $cleanDate -replace '\s+', ' '
        $cleanTime = $cleanTime -replace '\s+', ' '

        if ([string]::IsNullOrWhiteSpace($cleanDate)) {
            throw "Date is empty."
        }

        if ([string]::IsNullOrWhiteSpace($cleanTime)) {
            throw "LocalTime is empty."
        }

        if ([string]::IsNullOrWhiteSpace($TimeZoneId)) {
            throw "TimeZoneId is empty."
        }

        # Normalize common time input, e.g. "17:00" is allowed.
        $localText = "$cleanDate $cleanTime"
        $localText = $localText.Trim() -replace '\s+', ' '

        $dateFormats = [string[]]@(
            'yyyy-MM-dd HH:mm:ss',
            'yyyy-MM-dd H:mm:ss',
            'yyyy-MM-dd HH:mm',
            'yyyy-MM-dd H:mm',

            'MM/dd/yyyy HH:mm:ss',
            'M/d/yyyy HH:mm:ss',
            'MM/dd/yyyy H:mm:ss',
            'M/d/yyyy H:mm:ss',

            'MM/dd/yyyy HH:mm',
            'M/d/yyyy HH:mm',
            'MM/dd/yyyy H:mm',
            'M/d/yyyy H:mm'
        )

        $localUnspecified = [DateTime]::MinValue

        $parsed = [DateTime]::TryParseExact(
            $localText,
            $dateFormats,
            $culture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$localUnspecified
        )

        if (-not $parsed) {
            throw "Could not parse local date/time '$localText'. Expected formats like yyyy-MM-dd HH:mm:ss, yyyy-MM-dd HH:mm, MM/dd/yyyy HH:mm:ss, or MM/dd/yyyy HH:mm."
        }

        # This is critical: the parsed value is a wall-clock time in the target timezone.
        $localUnspecified = [DateTime]::SpecifyKind($localUnspecified, [DateTimeKind]::Unspecified)

        try {
            $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
        }
        catch {
            throw "Could not find timezone '$TimeZoneId'. If you are using Windows PowerShell 5.1, IANA timezone IDs like 'Australia/Lord_Howe' may not work. Use PowerShell 7 or map it to a Windows timezone ID."
        }

        if ($tz.IsInvalidTime($localUnspecified)) {
            throw "The local time '$localText' is invalid in timezone '$TimeZoneId' because of a daylight-saving transition."
        }

        $isAmbiguous = $tz.IsAmbiguousTime($localUnspecified)
        if ($isAmbiguous) {
            Write-Warning "The local time '$localText' is ambiguous in timezone '$TimeZoneId' because of a daylight-saving transition."
        }

        $utcDateTime = [System.TimeZoneInfo]::ConvertTimeToUtc($localUnspecified, $tz)
        $utcOffset = $tz.GetUtcOffset($localUnspecified)

        $utcDateTimeOffset = [DateTimeOffset]::new(
            [DateTime]::SpecifyKind($utcDateTime, [DateTimeKind]::Utc)
        )

        $epochUtc = $utcDateTimeOffset.ToUnixTimeSeconds()

        return [pscustomobject]@{
            Date                 = $localUnspecified.ToString('yyyy-MM-dd', $culture)
            LocalTime            = $localUnspecified.ToString('HH:mm:ss', $culture)
            DisplayTime          = $localUnspecified.ToString('h:mm tt', $culture)
            Timezone             = $TimeZoneId
            UtcOffset            = $utcOffset.ToString()
            UtcDateTime          = $utcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ", $culture)
            DatetimeEpochUtc     = $epochUtc
            IsAmbiguousLocalTime = $isAmbiguous
        }
    }
    function Convert-To12HourTime {
        param([string]$TimeText)

        if ([string]::IsNullOrWhiteSpace($TimeText)) {
            return $null
        }

        $cleanTime = $TimeText.Trim().Trim('"', "'")

        $formats = [string[]]@(
            'HH:mm:ss',
            'H:mm:ss',
            'HH:mm',
            'H:mm'
        )

        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        $styles = [System.Globalization.DateTimeStyles]::None
        $dt = [DateTime]::MinValue

        if (-not [DateTime]::TryParseExact($cleanTime, $formats, $culture, $styles, [ref]$dt)) {
            throw "get12hourtime() could not parse time '$TimeText'. Cleaned value was '$cleanTime'. Expected HH:mm:ss, H:mm:ss, HH:mm, or H:mm."
        }

        return $dt.ToString('h:mm tt', $culture)
    }

    function Split-DynamicArgumentText {
        param([string]$Text)

        if ($null -eq $Text -or $Text.Length -eq 0) { return @() }

        $parts = [System.Collections.Generic.List[string]]::new()
        $sb = [System.Text.StringBuilder]::new()
        $inS = $false
        $inD = $false
        $squareDepth = 0
        $parenthesisDepth = 0
        $braceDepth = 0

        for ($index = 0; $index -lt $Text.Length; $index++) {
            $ch = $Text[$index]
            $escaped = $index -gt 0 -and $Text[$index - 1] -eq '`'

            switch ($ch) {
                "'" {
                    if (-not $inD -and -not $escaped) { $inS = -not $inS }
                    [void]$sb.Append($ch)
                }

                '"' {
                    if (-not $inS -and -not $escaped) { $inD = -not $inD }
                    [void]$sb.Append($ch)
                }

                '[' {
                    if (-not $inS -and -not $inD) { $squareDepth++ }
                    [void]$sb.Append($ch)
                }

                ']' {
                    if (-not $inS -and -not $inD -and $squareDepth -gt 0) { $squareDepth-- }
                    [void]$sb.Append($ch)
                }

                '(' {
                    if (-not $inS -and -not $inD) { $parenthesisDepth++ }
                    [void]$sb.Append($ch)
                }

                ')' {
                    if (-not $inS -and -not $inD -and $parenthesisDepth -gt 0) { $parenthesisDepth-- }
                    [void]$sb.Append($ch)
                }

                '{' {
                    if (-not $inS -and -not $inD) { $braceDepth++ }
                    [void]$sb.Append($ch)
                }

                '}' {
                    if (-not $inS -and -not $inD -and $braceDepth -gt 0) { $braceDepth-- }
                    [void]$sb.Append($ch)
                }

                ',' {
                    if ($inS -or $inD -or $squareDepth -gt 0 -or $parenthesisDepth -gt 0 -or $braceDepth -gt 0) {
                        [void]$sb.Append($ch)
                    }
                    else {
                        $parts.Add($sb.ToString())
                        [void]$sb.Clear()
                    }
                }

                default {
                    [void]$sb.Append($ch)
                }
            }
        }

        if ($inS -or $inD -or $squareDepth -ne 0 -or $parenthesisDepth -ne 0 -or $braceDepth -ne 0) {
            throw "Dynamic arguments contain unbalanced quotes or delimiters: '$Text'."
        }

        # Add final argument, even if empty
        $parts.Add($sb.ToString())

        return $parts.ToArray()
    }

    function Split-DynamicArgs {
        param([string]$Text)

        $parts = @(Split-DynamicArgumentText -Text $Text)

        return $parts | ForEach-Object {
            $raw = $_

            # Trim only enough to detect whether the whole value is quoted.
            # This allows: abc, ' value ' ,+
            $check = $raw.Trim()

            if ($check.Length -ge 2 -and
                (
                    ($check.StartsWith("'") -and $check.EndsWith("'")) -or
                    ($check.StartsWith('"') -and $check.EndsWith('"'))
                )) {
                # Quoted value: remove wrapping quotes, but do NOT trim inside
                $quoteChar = $check.Substring(0, 1)

                # Find the quoted content from the trimmed wrapper
                $s = $check.Substring(1, $check.Length - 2)

                return $s
            }
            else {
                # Unquoted value: normal trim
                return $raw.Trim()
            }
        }
    }

    function Resolve-DynamicReference {
        param(
            [Parameter(Mandatory)]
            [string]$ReferencePath
        )

        if ($null -eq $MappedAdapter) {
            throw "Dynamic reference '$ReferencePath' cannot be resolved because MappedTokenAdapter was not provided."
        }

        if ($ReferencePath.StartsWith('Dynamic.', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Dynamic references cannot target another Dynamic token: '$ReferencePath'."
        }

        $referencePlan = [pscustomobject]@{
            Path = $ReferencePath
        }

        if ($null -ne $Plan -and $null -ne $Plan.Config) {
            $referencePlan | Add-Member -MemberType NoteProperty -Name Config -Value $Plan.Config
        }

        $referenceSignal = $MappedAdapter.Invoke(
            $null,
            'Get',
            $Signal,
            $referencePlan,
            $ItemSignal
        ) | Select-Object -Last 1

        $null = $opSignal.MergeSignal($referenceSignal)

        if ($referenceSignal.Failure()) {
            throw "Dynamic reference '$ReferencePath' failed to resolve."
        }

        if (-not $referenceSignal.HasResult()) {
            throw "Dynamic reference '$ReferencePath' was not found or resolved to null."
        }

        # Wrapping Value prevents PowerShell from enumerating array results.
        return [pscustomobject]@{
            Value = $referenceSignal.GetResult()
        }
    }

    function Resolve-DynamicArguments {
        param(
            [string]$Text,
            [hashtable]$ReferenceCache
        )

        $arguments = [System.Collections.Generic.List[object]]::new()
        $hasReferences = $false

        foreach ($argumentText in @(Split-DynamicArgumentText -Text $Text)) {
            $check = $argumentText.Trim()
            $isQuoted = $check.Length -ge 2 -and (
                ($check.StartsWith("'") -and $check.EndsWith("'")) -or
                ($check.StartsWith('"') -and $check.EndsWith('"'))
            )

            if ($isQuoted) {
                $arguments.Add($check.Substring(1, $check.Length - 2))
                continue
            }

            if ($check -match '(?s)^\[(?<path>.+)~\]$') {
                $referencePath = $matches['path'].Trim()
                if ([string]::IsNullOrWhiteSpace($referencePath)) {
                    throw "Dynamic reference path cannot be empty."
                }

                if (-not $ReferenceCache.ContainsKey($referencePath)) {
                    $ReferenceCache[$referencePath] = Resolve-DynamicReference -ReferencePath $referencePath
                }

                $arguments.Add($ReferenceCache[$referencePath].Value)
                $hasReferences = $true
                continue
            }

            if ($check -match '~\]') {
                throw "Dynamic reference tokens must occupy an entire unquoted argument: '$check'."
            }

            $arguments.Add($check)
        }

        return [pscustomobject]@{
            Arguments     = $arguments
            HasReferences = $hasReferences
        }
    }

    function ConvertTo-DynamicCollection {
        param(
            [object]$Value,
            [Parameter(Mandatory)]
            [string]$FunctionName
        )

        if ($null -eq $Value) {
            return [pscustomobject]@{ Items = [object[]]@() }
        }

        if ($Value -is [string]) {
            $trimmedValue = $Value.Trim()
            if ($trimmedValue.StartsWith('[') -and $trimmedValue.EndsWith(']')) {
                try {
                    return [pscustomobject]@{
                        Items = [object[]]@($trimmedValue | ConvertFrom-Json -Depth 100)
                    }
                }
                catch {
                    throw "$FunctionName received an invalid JSON array: $Value"
                }
            }

            throw "$FunctionName requires an array or collection."
        }

        if ($Value -isnot [System.Collections.IEnumerable]) {
            throw "$FunctionName requires an array or collection. ($($Value.GetType().FullName) was supplied)"
        }

        return [pscustomobject]@{
            Items = [object[]]@($Value)
        }
    }

    function ConvertTo-DynamicObjectValues {
        param(
            [object]$Value,
            [Parameter(Mandatory)]
            [string]$FunctionName
        )

        if ($Value -is [string]) {
            try {
                $Value = $Value | ConvertFrom-Json -Depth 100
            }
            catch {
                throw "$FunctionName received invalid JSON: $Value"
            }
        }

        $values = [System.Collections.Generic.List[object]]::new()

        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($key in $Value.Keys) {
                $values.Add($Value[$key])
            }
        }
        elseif ($Value -is [pscustomobject]) {
            foreach ($property in $Value.PSObject.Properties) {
                $values.Add($property.Value)
            }
        }
        else {
            throw "$FunctionName requires a JSON object, dictionary, or PSCustomObject."
        }

        return [pscustomobject]@{
            Items = $values
        }
    }

    function ConvertTo-DynamicMembershipValues {
        param(
            [object]$Value,
            [bool]$SplitString
        )

        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            return [pscustomobject]@{ Items = [object[]]@($Value) }
        }

        if ($Value -is [string]) {
            $trimmedValue = $Value.Trim()
            if ($trimmedValue.StartsWith('[') -and $trimmedValue.EndsWith(']')) {
                try {
                    return [pscustomobject]@{
                        Items = [object[]]@($trimmedValue | ConvertFrom-Json -Depth 100)
                    }
                }
                catch {
                    throw "Membership comparison received an invalid JSON array: $Value"
                }
            }

            if ($SplitString) {
                return [pscustomobject]@{
                    Items = [object[]]@(
                        $Value -split ',' |
                            ForEach-Object { $_.Trim() } |
                            Where-Object { $_ -ne '' }
                    )
                }
            }
        }

        return [pscustomobject]@{ Items = [object[]]@($Value) }
    }

    function ConvertTo-DynamicBoolean {
        param([object]$Value)

        if ($null -eq $Value) { return $false }
        if ($Value -is [bool]) { return $Value }

        if ($Value -is [string]) {
            return $Value.Trim().Equals('true', [StringComparison]::OrdinalIgnoreCase)
        }

        return [bool]$Value
    }

    function Split-DynamicArgsWithTail {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Text,

            [Parameter(Mandatory)]
            [int]$TailCount
        )

        if ($TailCount -lt 1) {
            throw "TailCount must be at least 1."
        }

        if ($null -eq $Text) {
            throw "Text cannot be null."
        }

        $allArgs = @(Split-DynamicArgs $Text)

        if ($allArgs.Count -lt $TailCount + 1) {
            throw "Expected at least $($TailCount + 1) arguments, but got $($allArgs.Count)."
        }

        # Walk backward through the original raw text and find the commas that
        # separate the final TailCount args, respecting quotes.
        $inS = $false
        $inD = $false
        $splitIndexes = @()

        for ($i = $Text.Length - 1; $i -ge 0; $i--) {
            $ch = $Text[$i]

            switch ($ch) {
                "'" {
                    if (-not $inD) {
                        $inS = -not $inS
                    }
                }

                '"' {
                    if (-not $inS) {
                        $inD = -not $inD
                    }
                }

                ',' {
                    if (-not $inS -and -not $inD) {
                        $splitIndexes += $i

                        if ($splitIndexes.Count -eq $TailCount) {
                            break
                        }
                    }
                }
            }
        }

        if ($splitIndexes.Count -lt $TailCount) {
            throw "Could not find $TailCount trailing argument separator(s) in '$Text'."
        }

        # Last found comma boundary separates raw value from trailing control args.
        $boundary = $splitIndexes[$TailCount - 1]

        $valueText = $Text.Substring(0, $boundary).Trim()
        if ($valueText.Substring(0,1) -eq '"' -and $valueText.Substring($valueText.Length-1,1) -eq '"') {
            $valueText = $valueText.Substring(1, $valueText.Length-2)
        }
        elseif ($valueText.Substring(0,1) -eq "'" -and $valueText.Substring($valueText.Length-1,1) -eq "'") {
            $valueText = $valueText.Substring(1, $valueText.Length-2)
        }

        $tailText = $Text.Substring($boundary + 1).Trim()

        $tailArgs = @(Split-DynamicArgs $tailText)

        if ($tailArgs.Count -lt $TailCount) {
            throw "Expected at least $TailCount trailing argument(s), but parsed $($tailArgs.Count): '$tailText'"
        }
        
        return [pscustomobject]@{
            ValueText = $valueText
            TailArgs  = $tailArgs
            AllArgs   = $allArgs
            TailText  = $tailText
        }
    }

    function Split-DynamicArgs-previous {
        param([string]$Text)
        if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

        $parts = @()
        $sb = [System.Text.StringBuilder]::new()
        $inS = $false; $inD = $false

        foreach ($ch in $Text.ToCharArray()) {
            switch ($ch) {
                "'" { if (-not $inD) { $inS = -not $inS }; [void]$sb.Append($ch) }
                '"' { if (-not $inS) { $inD = -not $inD }; [void]$sb.Append($ch) }
                ',' {
                    if ($inS -or $inD) { [void]$sb.Append($ch) }
                    else { $parts += $sb.ToString().Trim(); [void]$sb.Clear() }
                }
                default { [void]$sb.Append($ch) }
            }
        }
        if ($sb.Length -gt 0) { $parts += $sb.ToString().Trim() }

        # Strip one layer of wrapping quotes
        return $parts | ForEach-Object {
            $s = $_
            if ($s.Length -ge 2 -and
                (( $s.StartsWith("'") -and $s.EndsWith("'")) -or ( $s.StartsWith('"') -and $s.EndsWith('"')))) {
                $s = $s.Substring(1, $s.Length - 2)
            }
            $s
        }
    }

    function Indent {
        param([string]$Text, [int]$Level)
        $prefix = " " * ($Level * 2)
        return ($Text -split "`n" | ForEach-Object { $prefix + $_ }) -join "`n"
    }

    function Format-Scalar {
        param($Value)
        if ($null -eq $Value) { return "<null>" }
        return "$Value"
    }

    function Format-Object {
        param(
            [pscustomobject]$Obj,
            [int]$IndentLevel = 0
        )

        $lines = @()

        foreach ($prop in $Obj.PSObject.Properties) {
            $name  = $prop.Name
            $value = $prop.Value

            # Array?
            if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                $formattedItems = @()

                foreach ($item in $value) {
                    if ($item -is [pscustomobject]) {
                        $inner = Format-Object -Obj $item -IndentLevel ($IndentLevel + 1)
                        $formattedItems += (Indent $inner ($IndentLevel + 1))
                    }
                    else {
                        $formattedItems += (Indent (Format-Scalar $item) ($IndentLevel + 1))
                    }
                }

                $lines += "$($name):`n$($formattedItems -join "`n")"
                continue
            }

            # Nested object?
            if ($value -is [pscustomobject]) {
                $inner = Format-Object -Obj $value -IndentLevel ($IndentLevel + 1)
                $lines += "$($name):`n$(Indent $inner ($IndentLevel + 1))"
                continue
            }

            # Scalar
            $lines += "$($name): $(Format-Scalar $value)"
        }

        return ($lines -join "`n")
    }

    function Format-Array {
        param(
            [System.Collections.IEnumerable]$Arr,
            [int]$IndentLevel = 0
        )

        $blocks = @()

        foreach ($item in $Arr) {
            if ($item -is [pscustomobject]) {
                $blocks += (Format-Object -Obj $item -IndentLevel $IndentLevel)
            }
            else {
                $blocks += (Format-Scalar $item)
            }
        }

        return ($blocks -join "`n`n")
    }

    function Invoke-ParseOffset {
        param([string]$Text)

        if ([string]::IsNullOrWhiteSpace($Text)) { return [TimeSpan]::Zero }

        $t = $Text.Trim()
        $sgn = 1
        if ($t.StartsWith('+')) { $t = $t.Substring(1) }
        elseif ($t.StartsWith('-')) { $sgn = -1; $t = $t.Substring(1) }

        $m = [regex]::Matches($t, '(\d+)([smhdw])', 'IgnoreCase')
        if ($m.Count -eq 0) {
            throw "Resolve-DynamicPath: invalid offset '$Text'; use +7d, -2h, +90m, +1w, +1h30m, etc."
        }

        $total = [TimeSpan]::Zero
        foreach ($g in $m) {
            $n = [int]$g.Groups[1].Value
            switch ($g.Groups[2].Value.ToLowerInvariant()) {
                's' { $total += [TimeSpan]::FromSeconds($n) }
                'm' { $total += [TimeSpan]::FromMinutes($n) }
                'h' { $total += [TimeSpan]::FromHours($n) }
                'd' { $total += [TimeSpan]::FromDays($n) }
                'w' { $total += [TimeSpan]::FromDays(7 * $n) }
            }
        }

        if ($sgn -lt 0) { $total = - $total }
        return $total
    }

    try {
        # 2) Extract expression after ::
        $expr = ($Path -replace '^\s*::', '').Trim()

        # 4) Parse dynamic function: name(args...)
        #        if ($expr -notmatch '^(?<fn>[A-Za-z_]\w*)\s*(?:\((?<rawArgs>.*)\))?$') {
        #            throw "Resolve-DynamicPath: invalid dynamic expression '$Path'"
        #        }

        # Line Break Safe
        if ($expr -notmatch '^(?<fn>[A-Za-z_]\w*)\s*(?:\((?s)(?<rawArgs>.*)\))?$') {
            throw "Resolve-DynamicPath: invalid dynamic expression '$Path'"
        }

        $fn = $matches['fn'].ToLowerInvariant()
        $raw = ($matches['rawArgs'] ?? '').Trim()
        $rawArgs = Split-DynamicArgs $raw
        $referenceCache = @{}
        $resolvedArgumentSet = Resolve-DynamicArguments -Text $raw -ReferenceCache $referenceCache
        $resolvedArgs = $resolvedArgumentSet.Arguments

        switch ($fn) {
            'formatjsonastext' {
                if ($resolvedArgs.Count -ne 1) {
                    throw "FormatJsonAsText() requires exactly one argument. ($($resolvedArgs.Count) was supplied)"
                }

                $InputObject = $resolvedArgs[0]
                if ($InputObject -is [string]) {
                    $InputObject = $InputObject | ConvertFrom-Json -Depth 100
                }
                $combinedText = ""

                    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
                        $combinedText = Format-Array $InputObject
                    }
                    elseif ($InputObject -is [pscustomobject]) {
                        $combinedText = Format-Object $InputObject
                    }
                    else {
                        $combinedText = Format-Scalar $InputObject
                    }

                    $opSignal.SetResult($combinedText)
                    break
                }
            'getfileextension' {
                if ($resolvedArgs.Count -ne 1) {
                    throw "GetFileExtension() requires one argument. ($($resolvedArgs.Count) was supplied)"
                }

                $result = [System.IO.Path]::GetExtension([string]$resolvedArgs[0]).TrimStart('.')

                $opSignal.SetResult($result)
                return $opSignal
            }

            'getinitials' {
                if ($resolvedArgumentSet.HasReferences) {
                    if ($resolvedArgs.Count -ne 1) {
                        throw "GetInitials() with a typed reference requires one argument. ($($resolvedArgs.Count) was supplied)"
                    }

                    $value = [string]$resolvedArgs[0]
                }
                else {
                    $value = $raw
                }

                $result = $value -creplace '[^A-Z]', ''
                $opSignal.SetResult($result)
                return $opSignal
            }
 
            'removequotes' {
                if ($resolvedArgumentSet.HasReferences) {
                    if ($resolvedArgs.Count -ne 1) {
                        throw "RemoveQuotes() with a typed reference requires one argument. ($($resolvedArgs.Count) was supplied)"
                    }

                    $value = [string]$resolvedArgs[0]
                }
                else {
                    $value = $raw
                }

                $result = $value -replace '"', ''
                $result = $result -replace "'", ""
                $opSignal.SetResult($result)
                return $opSignal
            }
            'replace' {
                if ($resolvedArgumentSet.HasReferences) {
                    if ($resolvedArgs.Count -ne 3) {
                        throw "Replace() with typed references requires exactly three arguments: value, match, and replacement."
                    }

                    $value = [string]$resolvedArgs[0]
                    $matchValue = [string]$resolvedArgs[1]
                    $replaceValue = [string]$resolvedArgs[2]
                }
                else {
                    $parsed = Split-DynamicArgsWithTail -Text $raw -TailCount 2
                    if ($null -eq $parsed -or $parsed.TailArgs.Count -ne 2) {
                        throw "Replace() requires a value, match, and replacement argument."
                    }

                    $value = $parsed.ValueText
                    $matchValue = $parsed.TailArgs[0]
                    $replaceValue = $parsed.TailArgs[1]
                }

                $finalValue = $value -replace [regex]::Escape($matchValue), $replaceValue

                $opSignal.SetResult($finalValue)
                return $opSignal
            }

            'null' {
                $opSignal.SetResult($null)
                return $opSignal
            }

            'guid' {
                $opSignal.SetResult([guid]::NewGuid().ToString())
                return $opSignal
            }

            'gt' {
                if ($resolvedArgs.Count -ne 2) {
                    throw "GreaterThan() requires two arguments. ($($resolvedArgs.Count) was supplied)"
                }

                $result = [int]$resolvedArgs[0] -gt [int]$resolvedArgs[1]

                $opSignal.SetResult($result)
                return $opSignal
            }

            'lt' {
                if ($resolvedArgs.Count -ne 2) {
                    throw "LesserThan() requires two arguments. ($($resolvedArgs.Count) was supplied)"
                }

                $result = [int]$resolvedArgs[0] -lt [int]$resolvedArgs[1]

                $opSignal.SetResult($result)
                return $opSignal
            }

            'add' {
                if ($resolvedArgs.Count -ne 2) {
                    throw "Add() requires two arguments. ($($resolvedArgs.Count) was supplied)"
                }

                $result = [int]$resolvedArgs[0] + [int]$resolvedArgs[1]

                $opSignal.SetResult($result)
                return $opSignal
            }

            'subtract' {
                if ($resolvedArgs.Count -ne 2) {
                    throw "Subtract() requires two arguments. ($($resolvedArgs.Count) was supplied)"
                }

                $result = [int]$resolvedArgs[0] - [int]$resolvedArgs[1]

                $opSignal.SetResult($result)
                return $opSignal
            }

            'if' {
                if ($resolvedArgumentSet.HasReferences) {
                    if ($resolvedArgs.Count -ne 3) {
                        throw "If() with typed references requires exactly three arguments: condition, true value, and false value."
                    }

                    $value = ConvertTo-DynamicBoolean $resolvedArgs[0]
                    $trueValue = $resolvedArgs[1]
                    $falseValue = $resolvedArgs[2]
                }
                else {
                    $parsed = Split-DynamicArgsWithTail -Text $raw -TailCount 2
                    if ($null -eq $parsed -or $parsed.TailArgs.Count -ne 2) {
                        throw "If() requires a condition, true value, and false value."
                    }

                    $value = ConvertTo-DynamicBoolean $parsed.ValueText
                    $trueValue = $parsed.TailArgs[0]
                    $falseValue = $parsed.TailArgs[1]
                }

                if ($value) {
                    $result = $trueValue
                }
                else {
                    $result = $falseValue
                    if ($result -eq 'null') {
                        $result = $null
                    }
                }

                $opSignal.SetResult($result)
                return $opSignal
            }

            'toarray' {
                if ($resolvedArgumentSet.HasReferences) {
                    if ($resolvedArgs.Count -ne 2) {
                        throw "ToArray() with a typed reference requires a source value and one trailing delimiter argument."
                    }

                    $value = $resolvedArgs[0]
                    $delimiter = [string]$resolvedArgs[1]
                }
                else {
                    $parsed = Split-DynamicArgsWithTail -Text $raw -TailCount 1
                    if ($null -eq $parsed -or $parsed.TailArgs.Count -ne 1 -or [string]::IsNullOrEmpty($parsed.ValueText)) {
                        throw "ToArray() requires a source value and one trailing delimiter argument."
                    }

                    $value = $parsed.ValueText
                    $delimiter = $parsed.TailArgs[0]
                }

                if ([string]::IsNullOrEmpty($delimiter)) {
                    throw "ToArray() delimiter cannot be empty."
                }

                if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                    $result = [object[]]@($value)
                }
                else {
                    $result = [string]$value -split [regex]::Escape($delimiter)
                }

                $opSignal.SetResult($result)
                return $opSignal
            }

            'substring' {
                if ($resolvedArgumentSet.HasReferences) {
                    if ($resolvedArgs.Count -ne 3) {
                        throw "Substring() with typed references requires exactly three arguments: value, position, and length."
                    }

                    [string]$value = $resolvedArgs[0]
                    [string]$positionArgument = $resolvedArgs[1]
                    [int]$length = $resolvedArgs[2]
                }
                else {
                    $parsed = Split-DynamicArgsWithTail -Text $raw -TailCount 2

                    if ($null -eq $parsed -or $parsed.TailArgs.Count -ne 2) {
                        throw "Substring() requires a source value, a position argument, and a trailing length argument."
                    }

                    [string]$value = $parsed.ValueText
                    [string]$positionArgument = $parsed.TailArgs[0]
                    [int]$length = $parsed.TailArgs[1]
                }

                if ($length -lt 0) {
                    throw "substring() length must be >= 0. ($length supplied)"
                }

                switch ($positionArgument.ToLowerInvariant()) {
                    'first' {
                        $startIndex = 0
                    }

                    'last' {
                        $startIndex = [math]::Max(0, $value.Length - $length)
                    }

                    default {
                        [int]$startIndex = 0

                        if (-not [int]::TryParse($positionArgument, [ref]$startIndex)) {
                            throw "substring() position must be 'first', 'last', or a numeric starting position. ('$positionArgument' supplied)"
                        }

                        if ($startIndex -lt 0) {
                            throw "substring() starting position must be >= 0. ($startIndex supplied)"
                        }

                        if ($startIndex -gt $value.Length) {
                            throw "substring() starting position cannot exceed the source length of $($value.Length). ($startIndex supplied)"
                        }
                    }
                }

                # Clamp the requested length to the number of available characters.
                $availableLength = $value.Length - $startIndex
                $actualLength = [math]::Min($length, $availableLength)

                $result = $value.Substring($startIndex, $actualLength)

                $opSignal.SetResult($result)
                return $opSignal
            }

            'getindex' {
                if ($resolvedArgumentSet.HasReferences) {
                    if ($resolvedArgs.Count -ne 2) {
                        throw "GetIndex with a typed reference requires exactly two arguments: collection and index. ($($resolvedArgs.Count) was supplied)"
                    }

                    $source = $resolvedArgs[0]
                    if ($source -is [string] -or $source -isnot [System.Collections.IEnumerable]) {
                        throw "GetIndex typed source must be a non-string collection. ($($source.GetType().FullName) was supplied)"
                    }

                    $array = @($source)
                    $index = [int]$resolvedArgs[1]
                }
                else {
                    if ($rawArgs.Count -lt 2) {
                        throw "GetIndex requires at least two arguments. ($($rawArgs.Count) was supplied)"
                    }

                    # Legacy behavior: the final argument is the index and all
                    # preceding arguments form the collection.
                    $index = [int]$rawArgs[-1]
                    $array = @($rawArgs[0..($rawArgs.Count - 2)])
                }

                # Convert negative index to reverse lookup
                # -1 = last item, -2 = second-to-last, etc.
                if ($index -lt 0) {
                    $index = $array.Count + $index
                }

                # Validate index after conversion
                if ($index -lt 0 -or $index -ge $array.Count) {
                    $opSignal.LogWarning("Index $index is out of bounds for array of size $($array.Count)")
                    $result = $null
                }
                else {
                    $result = $array[$index]
                }

                $opSignal.SetResult($result)
                return $opSignal
            }

            'toint' {
                if ($resolvedArgs.Count -ne 1) {
                    throw "ToInt() requires one argument. ($($resolvedArgs.Count) was supplied)"
                }

                $result = [int]$resolvedArgs[0]

                $opSignal.SetResult($result)
                return $opSignal
            }

            'tojson' {
                if ($resolvedArgs.Count -ne 1) {
                    throw "ToJson() requires one argument. ($($resolvedArgs.Count) was supplied)"
                }

                $result = ConvertTo-Json -InputObject $resolvedArgs[0] -Depth 100 -Compress

                $opSignal.SetResult($result)
                return $opSignal
            }

            'fromjson' {
                if ($resolvedArgs.Count -ne 1) {
                    throw "FromJson() requires one argument. ($($resolvedArgs.Count) was supplied)"
                }

                if ($resolvedArgs[0] -isnot [string]) {
                    throw "FromJson() requires a JSON string. ($($resolvedArgs[0].GetType().FullName) was supplied)"
                }

                $result = $resolvedArgs[0] | ConvertFrom-Json -Depth 100

                $opSignal.SetResult($result)
                return $opSignal
            }

            'join' {
                if ($resolvedArgs.Count -ne 2) {
                    throw "Join() requires exactly two arguments: an array and a delimiter. ($($resolvedArgs.Count) was supplied)"
                }

                $collection = ConvertTo-DynamicCollection -Value $resolvedArgs[0] -FunctionName 'Join()'
                $delimiter = [string]$resolvedArgs[1]

                $result = $collection.Items -join $delimiter

                $opSignal.SetResult($result)
                return $opSignal
            }

            'joinvalues' {
                if ($resolvedArgs.Count -ne 2) {
                    throw "JoinValues() requires exactly two arguments: an object and a delimiter. ($($resolvedArgs.Count) was supplied)"
                }

                $objectValues = ConvertTo-DynamicObjectValues -Value $resolvedArgs[0] -FunctionName 'JoinValues()'
                $delimiter = [string]$resolvedArgs[1]
                $result = $objectValues.Items -join $delimiter

                $opSignal.SetResult($result)
                return $opSignal
            }

            'joinarrays' {
                if ($resolvedArgs.Count -ne 2) {
                    throw "JoinArrays() requires exactly two arguments: nested arrays and a delimiter. ($($resolvedArgs.Count) was supplied)"
                }

                $outerCollection = ConvertTo-DynamicCollection -Value $resolvedArgs[0] -FunctionName 'JoinArrays()'
                $delimiter = [string]$resolvedArgs[1]

                $values = @()

                foreach ($inner in $outerCollection.Items) {
                    $innerCollection = ConvertTo-DynamicCollection -Value $inner -FunctionName 'JoinArrays()'
                    $values += ($innerCollection.Items -join '')
                }

                # Join all results with the delimiter
                $result = $values -join $delimiter

                $opSignal.SetResult($result)
                return $opSignal
            }

            'filldigits' {
                if ($resolvedArgs.Count -ne 2) {
                    throw "FillDigits() requires two arguments: number and digits. ($($resolvedArgs.Count) was supplied)"
                }

                $number = [int]$resolvedArgs[0]
                $digits = [int]$resolvedArgs[1]

                if ($digits -lt 1) {
                    throw "filldigits() digits must be greater than 0. ($digits was supplied)"
                }

                $result = $number.ToString("D$digits")

                $opSignal.SetResult($result)
                return $opSignal
            }

            'not' {
                if ($resolvedArgumentSet.HasReferences) {
                    if ($resolvedArgs.Count -ne 1) {
                        throw "Not() with a typed reference requires one argument. ($($resolvedArgs.Count) was supplied)"
                    }

                    $value = $resolvedArgs[0]
                }
                else {
                    if ($rawArgs.Count -lt 1) {
                        throw "Not() requires one argument."
                    }

                    $value = $rawArgs[0]
                }

                $result = -not (ConvertTo-DynamicBoolean $value)

                $opSignal.SetResult($result)
                return $opSignal
            }

            'notequals' {
                if ($resolvedArgumentSet.HasReferences) {
                    if ($resolvedArgs.Count -ne 2) {
                        throw "NotEquals() with typed references requires exactly two arguments."
                    }

                    $first = $resolvedArgs[0]
                    $second = $resolvedArgs[1]
                }
                else {
                    $parsed = Split-DynamicArgsWithTail -Text $raw -TailCount 1

                    if ($null -eq $parsed -or $parsed.TailArgs.Count -ne 1) {
                        throw "NotEquals() requires a leading value and one trailing comparison argument."
                    }

                    $first = $parsed.ValueText
                    $second = $parsed.TailArgs[0]
                }

                $result = $first -ne $second

                $opSignal.SetResult($result)
                return $opSignal
            }

            'equals' {
                if ($resolvedArgumentSet.HasReferences) {
                    if ($resolvedArgs.Count -ne 2) {
                        throw "Equals() with typed references requires exactly two arguments."
                    }

                    $first = $resolvedArgs[0]
                    $second = $resolvedArgs[1]
                }
                else {
                    $parsed = Split-DynamicArgsWithTail -Text $raw -TailCount 1

                    if ($null -eq $parsed -or $parsed.TailArgs.Count -ne 1) {
                        throw "Equals() requires a leading value and one trailing comparison argument."
                    }

                    $first = $parsed.ValueText
                    $second = $parsed.TailArgs[0]
                }

                $result = $first -eq $second

                $opSignal.SetResult($result)
                return $opSignal
            }

            'notin' {
                if ($resolvedArgs.Count -ne 2) {
                    throw "NotIn() requires exactly two arguments: a value and allowed values. ($($resolvedArgs.Count) was supplied)"
                }

                $value = (ConvertTo-DynamicMembershipValues -Value $resolvedArgs[0] -SplitString:$false).Items
                $allowedValues = (ConvertTo-DynamicMembershipValues -Value $resolvedArgs[1] -SplitString:$true).Items

                $result = @(
                    $allowedValues | Where-Object {
                        $_ -in $value
                    }
                ).Count -eq 0

                $opSignal.SetResult($result)
                return $opSignal
            }

            'in' {
                if ($resolvedArgs.Count -ne 2) {
                    throw "In() requires exactly two arguments: a value and allowed values. ($($resolvedArgs.Count) was supplied)"
                }

                $value = (ConvertTo-DynamicMembershipValues -Value $resolvedArgs[0] -SplitString:$false).Items
                $allowedValues = (ConvertTo-DynamicMembershipValues -Value $resolvedArgs[1] -SplitString:$true).Items

                $result = @(
                    $allowedValues | Where-Object {
                        $_ -in $value
                    }
                ).Count -gt 0

                $opSignal.SetResult($result)
                return $opSignal
            }

            'and' {
                $result = $resolvedArgs.Count -gt 0 -and @(
                    $resolvedArgs | Where-Object { -not (ConvertTo-DynamicBoolean $_) }
                ).Count -eq 0

                $opSignal.SetResult($result)
                return $opSignal

            }

            'or' {
                $result = $resolvedArgs.Count -gt 0 -and @(
                    $resolvedArgs | Where-Object { ConvertTo-DynamicBoolean $_ }
                ).Count -gt 0

                $opSignal.SetResult($result)
                return $opSignal
            }

            'isnull' {
                if ($resolvedArgumentSet.HasReferences) {
                    if ($resolvedArgs.Count -ne 1) {
                        throw "IsNull() with a typed reference requires one argument. ($($resolvedArgs.Count) was supplied)"
                    }

                    $hasValue = $true
                    $value = $resolvedArgs[0]
                }
                else {
                    $hasValue = $raw.Length -gt 0
                    $value = if ($rawArgs.Count -le 1) { $rawArgs[0] } else { $raw }
                }

                $result = -not $hasValue -or $null -eq $value
                $opSignal.SetResult($result)
                return $opSignal
            }

            'isnotnull' {
                if ($resolvedArgumentSet.HasReferences) {
                    if ($resolvedArgs.Count -ne 1) {
                        throw "IsNotNull() with a typed reference requires one argument. ($($resolvedArgs.Count) was supplied)"
                    }

                    $hasValue = $true
                    $value = $resolvedArgs[0]
                }
                else {
                    $hasValue = $raw.Length -gt 0
                    $value = if ($rawArgs.Count -le 1) { $rawArgs[0] } else { $raw }
                }

                $result = $hasValue -and $null -ne $value
                $opSignal.SetResult($result)
                return $opSignal
            }

            'isnotnullorempty' {
                if ($resolvedArgumentSet.HasReferences) {
                    if ($resolvedArgs.Count -ne 1) {
                        throw "IsNotNullOrEmpty() with a typed reference requires one argument. ($($resolvedArgs.Count) was supplied)"
                    }

                    $hasValue = $true
                    $value = $resolvedArgs[0]
                }
                else {
                    $hasValue = $raw.Length -gt 0
                    $value = if ($rawArgs.Count -le 1) { $rawArgs[0] } else { $raw }
                }

                $result = $hasValue -and -not [string]::IsNullOrEmpty([string]$value)
                $opSignal.SetResult($result)
                return $opSignal
            }

            'isnullorempty' {
                if ($resolvedArgumentSet.HasReferences) {
                    if ($resolvedArgs.Count -ne 1) {
                        throw "IsNullOrEmpty() with a typed reference requires one argument. ($($resolvedArgs.Count) was supplied)"
                    }

                    $hasValue = $true
                    $value = $resolvedArgs[0]
                }
                else {
                    $hasValue = $raw.Length -gt 0
                    $value = if ($rawArgs.Count -le 1) { $rawArgs[0] } else { $raw }
                }

                $result = -not $hasValue -or [string]::IsNullOrEmpty([string]$value)
                $opSignal.SetResult($result)
                return $opSignal
            }

            'newguid' {
                $opSignal.SetResult([guid]::NewGuid().ToString())
                return $opSignal
            }

            'utcnow' {
                # Kusto datetime best practice: UTC ISO 8601 round-trip string ("o") with Z suffix
                # utcNow([offset])
                if ($resolvedArgs.Count -gt 1) {
                    throw "UtcNow() accepts zero or one offset argument. ($($resolvedArgs.Count) was supplied)"
                }

                $offset = [TimeSpan]::Zero
                if ($resolvedArgs.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace([string]$resolvedArgs[0])) {
                    $offset = Invoke-ParseOffset -Text ([string]$resolvedArgs[0])
                }

                $dt = [DateTime]::UtcNow + $offset
                $dtUtc = [DateTime]::SpecifyKind($dt, [DateTimeKind]::Utc)

                $opSignal.SetResult($dtUtc.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture))
                return $opSignal
            }

            'get12hourtime' {
                if ($resolvedArgs.Count -ne 1) {
                    throw "Get12HourTime() requires one argument. ($($resolvedArgs.Count) was supplied)"
                }

                $result = Convert-To12HourTime ([string]$resolvedArgs[0])

                $opSignal.SetResult($result)
                return $opSignal
            }

            'localtoutc' {
                if ($resolvedArgs.Count -ne 3) {
                    throw "LocalToUtc() requires three arguments: date, local time, and timezone. ($($resolvedArgs.Count) was supplied)"
                }

                $result = Convert-LocalDateTimeToUtc `
                    -Date ([string]$resolvedArgs[0]) `
                    -LocalTime ([string]$resolvedArgs[1]) `
                    -TimeZoneId ([string]$resolvedArgs[2])

                $opSignal.SetResult($result.UtcDateTime)
                return $opSignal
            }

            default {
                throw "Resolve-DynamicPath: unknown function '$fn' in '$Path'."
            }
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Resolve-DynamicPath ($Path): $_", $null, $_)
    }

    return $opSignal
}
