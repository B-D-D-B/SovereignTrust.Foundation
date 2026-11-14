<#
.SYNOPSIS
Resolves a sovereign module path signal from a structured WirePath.

.DESCRIPTION
Takes a hierarchical `WirePath` string of the format:
  `Project.Collection.Kind.Type[.Slot][.Key]`

Generates a `Signal` object encapsulating a jacket with all derived path components,
including folder location, filename, and hydration intent. This function does not perform
hydration or file access—only emits a sovereign signal for orchestration.

The resulting `Signal` can later be used to hydrate module manifests, register adapters,
or construct conductor graphs via SDA's pipeline.

.PARAMETER WirePath
A dot-delimited identifier string indicating the desired module location and identity.
Required format: `Project.Collection.Kind.Type[.Slot][.Key]`

.RETURNS
[Signal] A `Signal` object containing jacket metadata about the module path.

.EXAMPLE
$signal = Resolve-ModulePathSignal -WirePath "Core.SDK.Adapter.LocalFileSystem"

.NOTES
- This function replaces earlier graph-based constructions for module references.
- Intended as a sovereign primitive—non-hydrated, non-attached, signal-only.
- Use downstream in conjunction with Register-AdapterToMappedSlot or hydration condensers.

.AUTHOR
Neural Alchemist (SDA • BDDB)
#>


function Resolve-ModulePathSignal {
    param (
        [Parameter(Mandatory)][string]$WirePath
    )

    $opSignal = [Signal]::Start("Resolve-PathGraphForModule:$WirePath") | Select-Object -Last 1

    try {
        # ░▒▓█ VERIFY WIREPATH FORMAT █▓▒░
        $segments = $WirePath -split '\.'
        if ($segments.Count -lt 4) {
            $opSignal.LogCritical("WirePath must follow format Project.Collection.Kind.Type[.Slot][.Key]")
            return $opSignal
        }

        # ░▒▓█ EXTRACT COMPONENTS █▓▒░
        $project = $segments[0]
        $collection = $segments[1]
        $kind = $segments[2]
        $type = $segments[3]
        $slot = if ($segments.Count -ge 5) { $segments[4] } else { $null }
        $key = if ($segments.Count -ge 6) { $segments[5] } else { $null }

        $moduleStem = "$kind`_$type"
        $moduleName = "$moduleStem.psd1"

        $folderSegments = @("$project.$collection", 'Src', $kind, $type, 'PowerShell')
#        $relativeFolderPath = [System.IO.Path]::Combine($folderSegments)
        $relativeFolderPath = ($folderSegments -join '\')

        $relativeFilePath = Join-Path $relativeFolderPath $moduleName

        # ░▒▓█ BUILD MODULE SIGNAL █▓▒░
        $moduleSignal = [Signal]::Start("Module:$WirePath") | Select-Object -Last 1

        # Create a nested jacket signal to ensure sovereign structure
        $jacketSignal = [Signal]::Start("Jacket:$WirePath") | Select-Object -Last 1
        $jacketSignal.SetResult([ordered]@{
                Name               = $moduleName
                Project            = $project
                Collection         = $collection
                Kind               = $kind
                Type               = $type
                Slot               = $slot
                Key                = $key
                ModuleStem         = $moduleStem
                FullType           = $moduleStem
                RelativeFolderPath = $relativeFolderPath
                RelativeFilePath   = $relativeFilePath
                VirtualPath        = $WirePath
                HydrationIntent    = @(
                    @{
                        ConductionWirePath = "XYZ.Placeholder"
                        TargetPath         = "Modules.$moduleStem"
                        SourcePath         = $relativeFilePath
                        Format             = "psd1"
                        Timing             = "Sequential"
                    }
                )
            })

        $moduleSignal.SetJacket($jacketSignal)

        $opSignal.SetResult($moduleSignal)
        $opSignal.LogInformation("✅ Module signal prepared from WirePath: $WirePath")
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Resolve-PathGraphForModule: $_", $null, $_)
    }

    return $opSignal
}
