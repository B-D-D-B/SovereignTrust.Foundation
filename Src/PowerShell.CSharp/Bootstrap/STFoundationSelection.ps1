# Native-only copied-tree bootstrap; no product types are parsed here.
function Resolve-STSelectionPath {
    param([Parameter(Mandatory)][string]$Path, [switch]$Directory)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathFullyQualified($Path)) {
        throw 'ST_SELECTION_PATH: an absolute nonblank path is required.'
    }
    $full = [IO.Path]::GetFullPath($Path)
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if (($item -is [IO.DirectoryInfo]) -ne [bool]$Directory) { throw 'ST_SELECTION_PATH: wrong path kind.' }
    for ($current = $item; $null -ne $current; $current = $current.Parent) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "ST_SELECTION_REDIRECTION: $($current.FullName)"
        }
        if ($current -isnot [IO.DirectoryInfo]) { $current = $current.Directory; if ($null -eq $current) { break } }
    }
    return $item.FullName
}
. "$PSScriptRoot/STNativeSelection.ps1"
