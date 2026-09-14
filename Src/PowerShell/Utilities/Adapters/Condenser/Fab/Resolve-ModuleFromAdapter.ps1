function Resolve-ModuleFromAdapter {
    [CmdletBinding()]
    param (
        [Signal]$Signal,
        [string]$Slot,
        [string]$ModuleName,
        [string]$RelativePath
    )

    $opSignal = [Signal]::Start("Resolve-ModuleFromAdapter") | Select-Object -Last 1

    try {
        $adapterSignal = Resolve-PathFromDictionary -Dictionary ($Signal.GetControl($true)) -Path "%.*.#.Adapters.*.#.MappedStorage" -SignalLevel "Information" | Select-Object -Last 1

        $opSignal.MergeSignal($adapterSignal)

        if ($adapterSignal.Failure()) {
            $opSignal.LogCritical("Could not resolve MappedStorage adapter from signal.")
            return $opSignal
        }

        $adapter = $adapterSignal.GetResult() | Select-Object -Last 1
        while ($adapter -is [Signal]) {
            $adapter = $adapter.GetResult() | Select-Object -Last 1
        }

        # TODO: This should be moved into the adapter with the method name specifying embedded file system.

        if ($RelativePath -eq "SDAFusion.Adapters\Src\Token\SDA\PowerShell\Token_SDA.psd1")
        {
            $a = ""
        }

        $pathSignal = Resolve-ModulePathFromAdapter -Signal $Signal -Adapter $adapter -Slot $Slot -RelativePath $RelativePath | Select-Object -Last 1
#        $opSignal.MergeSignal($pathSignal)

        if ($pathSignal.Success()) {
            $modulePath = [string]$pathSignal.GetResult()
            Import-Module -Name $modulePath -Force -ErrorAction Stop

            $opSignal.LogInformation("✅ Module imported from path: $modulePath")
            $opSignal.SetResult([pscustomobject]@{
                Name = $ModuleName
                Path = $modulePath
            })
        } else {
            $opSignal.LogWarning("Could not resolve module path from adapter.")
            $opSignal.SetResult($pathSignal.GetResult())
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Resolve-ModuleFromAdapter: $($_.Exception.Message)", $null, $_)
    }

    return $opSignal
}
