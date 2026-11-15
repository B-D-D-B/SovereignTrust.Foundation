function Resolve-ModuleFromAdapter {
    [CmdletBinding()]
    param (
        [SignalGraph.Signal]$Signal,
        [string]$Slot,
        [string]$ModuleName,
        [string]$RelativePath
    )

    $opSignal = [SignalGraph.Signal]::Start("Resolve-ModuleFromAdapter") | Select-Object -Last 1

    try {
        $adapterSignal = Resolve-PathFromDictionary -Dictionary ($Signal.GetControl($true)) -Path "%.*.#.Adapters.*.#.MappedStorage" -SignalLevel "Information" | Select-Object -Last 1

        $opSignal.MergeSignal($adapterSignal)

        if ($adapterSignal.Failure()) {
            $opSignal.LogCritical("Could not resolve MappedStorage adapter from signal.")
            return $opSignal
        }

        $adapter = $adapterSignal.GetResult() | Select-Object -Last 1
        while ($adapter -is [SignalGraph.Signal]) {
            $adapter = $adapter.GetResult() | Select-Object -Last 1
        }

        # TODO: This should be moved into the adapter with the method name specifying embedded file system.

        if ($RelativePath -eq "SDAFusion.Adapters\Src\Token\SDA\PowerShell\Token_SDA.psd1")
        {
            $a = ""
        }

        $pathSignal = Resolve-ModulePathFromAdapter -Signal $Signal -Adapter $adapter -Slot $Slot -RelativePath $RelativePath | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure($pathSignal) -or -not $pathSignal.HasResult()) {
            $opSignal.LogCritical("Could not resolve module path from adapter.")
            return $opSignal
        }

        $modulePath = [string]$pathSignal.GetResult()
        $selection = Get-STWorkerSelection
        if ($null -ne $selection) {
            if ([IO.Path]::GetExtension($modulePath) -ne '.psd1') { throw 'ST_ENTRYPOINT: selected adapters require a guarded manifest.' }
            Assert-STSelectedEntryPoint -Selection $selection -EntryPoint $modulePath
            Assert-STFoundationSelection -Selection $selection -RequireLoaded
            Import-Module -Name $modulePath -ErrorAction Stop
            Assert-STFoundationSelection -Selection $selection -RequireLoaded
        } else { Import-Module -Name $modulePath -Force -ErrorAction Stop }

        $opSignal.LogInformation("✅ Module imported from path: $modulePath")
        $opSignal.SetResult([pscustomobject]@{
            Name = $ModuleName
            Path = $modulePath
        })
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Resolve-ModuleFromAdapter: $($_.Exception.Message)", $null, $_.Exception)
    }

    return $opSignal
}
