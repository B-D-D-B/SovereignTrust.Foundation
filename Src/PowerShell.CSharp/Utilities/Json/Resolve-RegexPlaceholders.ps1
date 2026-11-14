function Resolve-RegexPlaceholders {
    param (
        [Parameter(Mandatory)] $Merged,
        [Parameter(Mandatory)][string] $Pattern,
        [Parameter(Mandatory)][string] $InputString,
        [Parameter(Mandatory)][bool] $WarnOnMissing
    )

    $output = $InputString
    $Patternmatches = [regex]::Matches($InputString, $Pattern)

    foreach ($match in $Patternmatches) {
        $placeholder = $match.Value        # e.g., @@Item.Title
        $path = $match.Groups[1].Value     # e.g., Item.Title

        $value = Resolve-PathFromDictionaryNoSignal -Dictionary $Merged -Path $path

        if ($null -ne $value) {
            if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                $replacement = $value | ConvertTo-Json -Depth 20 -Compress
            }
            else {
                $replacement = $value.ToString()
            }

            $escaped = [regex]::Escape($placeholder)
            $output = $output -replace $escaped, $replacement
        }
        else {
            if ($WarnOnMissing) {
                Write-Host "[agent] Warning: No value found for placeholder '$placeholder'. Leaving it unchanged." -ForegroundColor Yellow
            }
        }
    }

    return $output
}
