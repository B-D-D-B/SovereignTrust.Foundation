# This was contained as Invoke-SDAFusion, but I stripped it down and made it into this Resolve-Conduit in order to be recursively used inside of a Conduction
<#
    Conduit is essentially a signal with a Conductor that's been resolved with the passed in Environment Jacket. 
    It provides a full scripted environment with all of the appropriate scripts and modules loaded to be used in stand-alone and silo parallel environments.
#>
function Resolve-Conduit {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [Signal]$EnvironmentSignal#,
        #        [object]$ConductionPlanRoute,
        #        [object]$ConductionContext
    )

    function Resolve-Environment() {
        [CmdletBinding()]
        param (
            [Signal]$ConductorSignal,
            [Signal]$EnvironmentSignal,
            [object]$Environment
        )

        $opSignal = [Signal]::Start("GenerateEnvironmentSignal", $ConductorSignal) | Select-Object -Last 1

        $EnvironmentSourceSignal = Invoke-CondenserAdapter -Slot "Memory" -Activity "Generate" -Signal $ConductorSignal -Plan $Environment -ItemSignal $EnvironmentSignal | Select-Object -Last 1
        if ($opSignal.MergeSignalAndVerifyFailure(@($EnvironmentSourceSignal))) {
            return $opSignal
        }

        # This won't scale when different runspaces have their own conduit with different adapter sets.
        $adapterSignal = Resolve-PathFromDictionary -Dictionary $ConductorSignal -Path "*.#.Adapters" -Default $null | Select-Object -Last 1
        if (-not $adapterSignal.HasResult()) {
            $adapterSignal = Resolve-PathFromDictionary -Dictionary $EnvironmentSignal -Path "*.#.Adapters.@.@.#"  | Select-Object -Last 1
            $ConductorSignal.CreateGraph()
            $ConductorSignal.GetPointer().RegisterSignal("Adapters", $adapterSignal)
        } else
        {
            Write-Host "Adapter Signal Already Mapped"
        }

        $adapterJsonSignal = Resolve-PathFromDictionary -Dictionary $EnvironmentSignal -Path "*.#.Adapters.@.@.#.Meta.%.@"  | Select-Object -Last 1
        $adapterJson = ConvertTo-Json -InputObject $adapterJsonSignal.GetResult() -Depth 100 -ErrorAction Stop
        Write-Host("AdapterJson: $adapterJson")

        # If the Environment is within the source object, resolve it.
        if ($EnvironmentSourceSignal.HasResult()) {
            $EnvironmentSource = $EnvironmentSourceSignal.GetResult()
            $MergeDetails = [PSCustomObject]@{
                Base               = $EnvironmentSource
                Overlay            = $Environment
                MergeArrayHandling = "Merge"
            }

            $MergeDetailsSignal = [Signal]::Start("Merge:EnvironmentSignal", $ConductorSignal) | Select-Object -Last 1
            $MergeDetailsSignal.SetResult($MergeDetails)

            $MergeDetailsJacketSignal = [Signal]::Start("Merge:EnvironmentSignal", $ConductorSignal) | Select-Object -Last 1
            $MergeDetailsJacketSignal.SetJacket($MergeDetailsSignal)

            $resultSignal = Invoke-CondenserAdapter -Slot "Transform" -Activity "Merge" -Signal $ConductorSignal -Plan $Environment -ItemSignal $MergeDetailsJacketSignal | Select-Object -Last 1
            if ($opSignal.MergeSignalAndVerifyFailure(@($resultSignal))) {
                return $opSignal
            }
            $Environment = $resultSignal.GetResult()
        }

        $opSignal.SetResult($ConductorSignal)
        return $opSignal
    }

    # ░▒▓█ START WRAPPER SIGNAL █▓▒░
    $opSignal = [Signal]::Start("Start-BondingConduction", $EnvironmentSignal) | Select-Object -Last 1

    $environmentJacket = $EnvironmentSignal.GetJacket()
    if ($null -eq $environmentJacket -or -not $environmentJacket.HasResult()) {
        $null = $opSignal.LogCritical("EnvironmentSignal must contain an environment definition in its jacket result.")
        return $opSignal
    }
    $Environment = $environmentJacket.GetResult()
    $ContentRootPathSignal = Resolve-PathFromDictionary -Dictionary $Environment -Path "Config.ContentRootPath" | Select-Object -Last 1
    if ($opSignal.MergeSignalAndVerifyFailure(@($ContentRootPathSignal))) {
        return $opSignal
    }
    if (-not $ContentRootPathSignal.HasResult() -or [string]::IsNullOrWhiteSpace([string]$ContentRootPathSignal.GetResult())) {
        $null = $opSignal.LogCritical("Environment Config.ContentRootPath is required.")
        return $opSignal
    }

    # Optionally run a test fusion session

    # Create a global console logger
#    $Global:ConsoleLoggerInstance = [ConsoleLogger]::new()
#    $Global:SignalTelemeter = [SignalTelemeter]::new()

    $bondingConductorSignal = Resolve-Conductor -Signal $opSignal | Select-Object -Last 1
    if ($opSignal.MergeSignalAndVerifyFailure(@($bondingConductorSignal))) {
        return $opSignal
    }

    $bondingConductor = $bondingConductorSignal.GetResult()

    $ConductorSignal = [Signal]::Start("EmbeddedFabRequest", $opSignal) | Select-Object -Last 1
    $ConductorSignal.SetJacket($bondingConductor.Signal)

        $ConductionSignal = [Signal]::Start("Conduction:EmbeddedFabRequest", $opSignal) | Select-Object -Last 1
        $ConductionSignal.SetJacket($ConductorSignal)

    # Hardwired initiation point of content adapter pointed to local storage - review pattern, should probably be passed in.
    $virtualPath = "SovereignTrust.Adapters.Storage.EmbeddedFileSystem.Content.Persistent.Read"

    $EmbeddedFileSystemConfig = [PSCustomObject]@{

        VirtualPath = $virtualPath
        Addresses   = @($ContentRootPathSignal.GetResult())
    }

    $EmbeddedFabRequestSignal = [Signal]::Start("EmbeddedFabRequest", $opSignal) | Select-Object -Last 1
    $EmbeddedFabRequestSignal.SetResult($EmbeddedFileSystemConfig)
    $EmbeddedFabRequestSignal.SetJacket($bondingConductor.Signal)

    $ItemSignal = [Signal]::Start("EmbeddedFabRequest", $opSignal) | Select-Object -Last 1
    $ItemSignal.SetJacket($EmbeddedFabRequestSignal)

    $FabResult = Invoke-CondenserAdapter -Slot "Fab" -Activity "Invoke" -Signal $EmbeddedFabRequestSignal -ItemSignal $ItemSignal
    if ($opSignal.MergeSignalAndVerifyFailure($FabResult)){
        return $opSignal
    }

    # Attach the Environment base content to the ConductorSignal Jacket Result in order to be able to generate it again later.
    Add-PathToDictionary -Dictionary $ConductorSignal -Path "%.@" -Value $EnvironmentSignal.GetJacket().GetResult()
    $EnvironmentConductorSignal = Resolve-Environment -ConductorSignal $ConductorSignal -EnvironmentSignal $EnvironmentSignal -Environment $Environment | Select-Object -Last 1
    if ($opSignal.MergeSignalAndVerifyFailure($EnvironmentConductorSignal)) {
        return $opSignal
    }

    $opSignal.SetResult($bondingConductorSignal.GetResult($true));
    return $opSignal
}
