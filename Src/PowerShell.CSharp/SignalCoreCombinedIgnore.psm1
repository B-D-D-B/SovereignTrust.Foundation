$Global:SignalFeedbackLevelMap = @{
    Unspecified           = 0
    SensitiveInformation  = 1
    VerboseInformation    = 2
    Information           = 4
    Warning               = 8
    Retry                 = 16
    Critical              = 32
}

$Global:SignalFeedbackNatureMap = @{
    Unspecified = 0
    Code        = 1
    Operations  = 2
    Security    = 4
    Content     = 8
}

function New-Signal {
    param (
        [string]$Name = "Unnamed",
        [object]$Result = $null
    )
    return [PSCustomObject]@{
        PSTypeName = 'Signal'
        Name       = $Name
        Result     = $Result
        Level      = 'Information'
        Entries    = @()
    }
}

function Add-SignalEntry {
    param (
        [Parameter(Mandatory)] $Signal,
        [Parameter(Mandatory)][ValidateSet("Unspecified", "SensitiveInformation", "VerboseInformation", "Information", "Warning", "Retry", "Critical")] [string]$Level,
        [Parameter(Mandatory)] [string]$Message,
        [Parameter()][ValidateSet("Unspecified", "Code", "Operations", "Security", "Content")] [string]$Nature = 'Unspecified',
        [Parameter()][Exception]$Exception
    )

    $entry = [PSCustomObject]@{
        Level       = $Level
        LevelValue  = $SignalFeedbackLevelMap[$Level]
        Nature      = $Nature
        NatureValue = $SignalFeedbackNatureMap[$Nature]
        Message     = $Message
        Exception   = $Exception?.Message
        CreatedDate = (Get-Date).ToString("o")
    }

    $Signal.Entries += $entry

    if ($SignalFeedbackLevelMap[$Level] -ge $SignalFeedbackLevelMap['Critical']) {
        $Signal.Level = 'Critical'
    } elseif ($SignalFeedbackLevelMap[$Level] -ge $SignalFeedbackLevelMap['Warning'] -and $Signal.Level -ne 'Critical') {
        $Signal.Level = 'Warning'
    }

    return $entry
}

function Merge-Signal {
    param (
        [Parameter(Mandatory)] $Target,
        [Parameter(Mandatory)] $Sources
    )

    foreach ($source in $Sources) {
        if ($source.Entries) {
            $Target.Entries += $source.Entries
            if ($SignalFeedbackLevelMap[$source.Level] -ge $SignalFeedbackLevelMap['Critical']) {
                $Target.Level = 'Critical'
            } elseif ($SignalFeedbackLevelMap[$source.Level] -ge $SignalFeedbackLevelMap['Warning'] -and $Target.Level -ne 'Critical') {
                $Target.Level = 'Warning'
            }
        }
    }

    return $Target
}

function Get-SignalStatus {
    param (
        [Parameter(Mandatory)] $Signal
    )
    return if ($Signal.Level -eq 'Critical') { 'Failure' } else { 'Success' }
}

function ConvertTo-SignalJson {
    param (
        [Parameter(Mandatory)] $Signal
    )
    return $Signal | ConvertTo-Json -Depth 10 -Compress
}

function ConvertFrom-SignalJson {
    param (
        [Parameter(Mandatory)] [string]$Json
    )
    return $Json | ConvertFrom-Json -Depth 10
}

