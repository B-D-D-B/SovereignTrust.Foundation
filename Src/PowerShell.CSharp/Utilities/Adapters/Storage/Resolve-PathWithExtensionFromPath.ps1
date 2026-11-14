function Resolve-PathWithExtensionFromPath {
    param (
        [Parameter(Mandatory)][Signal]$Signal,
        [Parameter(Mandatory)][string]$Path
    )

    $opSignal = [Signal]::Start("Resolve-PathWithExtensionFromPath:$Path", $Signal) | Select-Object -Last 1

    try {
        # Return as-is if path already ends with a known extension (case-insensitive)
        if ($Path -match '\.(?i:json|xml|txt|map)$') {
            $opSignal.SetResult($Path)
            return $opSignal
        }

        # Normalize segments to lowercase for comparison
        $segments = ($Path -split '[\\/]') | ForEach-Object { $_.ToLowerInvariant() }

        if ($segments -contains 'json') {
            $result = "$Path.json"
            $opSignal.LogInformation("🧩 Appended .json based on lowercase segment match.")
        }
        elseif ($segments -contains 'xml') {
            $result = "$Path.xml"
            $opSignal.LogInformation("🧩 Appended .xml based on lowercase segment match.")
        }
        elseif ($segments -contains 'text' -or $segments -contains 'txt') {
            $result = "$Path.txt"
            $opSignal.LogInformation("🧩 Appended .xml based on lowercase segment match.")
        }
        elseif ($segments -contains 'map' -or $segments -contains 'maps') {
            $result = "$Path.map"
            $opSignal.LogInformation("🧩 Appended .xml based on lowercase segment match.")
        }
        else {
            $result = $Path
            $opSignal.LogInformation("✅ No extension hint found; returned unchanged.")
        }

        $opSignal.SetResult($result)
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Resolve-PathWithExtensionFromPath: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}
