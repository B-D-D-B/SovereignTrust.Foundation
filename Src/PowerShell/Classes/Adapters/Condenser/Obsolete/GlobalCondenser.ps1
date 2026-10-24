<#
Class: GlobalCondenser
Purpose: Legacy proposal condenser.
ActivityScope: None
Activities: None; Invoke takes a proposal without Activity.
#>
class GlobalCondenser {
    [object]$MappedCondenserAdapter
    [object]$Conductor
    [Signal]$Signal  # Sovereign control signal

    GlobalCondenser() {
    }

    static [GlobalCondenser] Start([MappedCondenserAdapter]$mappedAdapter, [Conductor]$conductor) {
        $instance = [GlobalCondenser]::new()
        $instance.MappedCondenserAdapter = $mappedAdapter
        $instance.Conductor = $conductor
        $instance.Signal = [Signal]::Start("GraphCondenser")
        return $instance
    }

    [object] Condense($CondenseProposal, $CancellationToken = $null) {
        $opSignal = [Signal]::Start([object]::new()) | Select-Object -Last 1
        $result = $this.LoadItem($CondenseProposal, $opSignal.Result, $CondenseProposal.Wire, $CondenseProposal.WireMergeType, $CondenseProposal.Reload, $CondenseProposal.LoadLevel, $CondenseProposal.AutoRunConductionLevel)
        $opSignal.MergeSignal($result)
        return $opSignal
    }

    [object] Invoke($Slot, $Proposal, $CancellationToken = $null) {
        $opSignal = [Signal]::Start() | Select-Object -Last 1
        $result = $this.Condense($Proposal)
        $opSignal.MergeSignal($result)
        $opSignal.Result = $result.Result
        return $opSignal
    }

    [object] LoadItemContent($Wire, [bool]$Reload = $false) {
        $opSignal = [Signal]::Start() | Select-Object -Last 1

        if ([string]::IsNullOrWhiteSpace($Wire.VirtualPath)) {
            $opSignal.LogCritical("Wire has empty VirtualPath: $($Wire.Identifier)")
            return $opSignal
        }

        $documentSignal = $null

        if ($Wire.CatalogService) {
            $documentSignal = $this.Conductor.MappedStorageService.ReadDynamic(
                $Wire.VirtualPath,
                $Wire.DocumentFormat,
                "tokens",
                $Wire.Version,
                $Wire.Identifier,
                $Wire.Key
            )
        }

        if (-not $documentSignal -or $documentSignal.Failure) {
            $documentSignal = $this.Conductor.MappedStorageService.ReadDynamic(
                $Wire.VirtualPath,
                $Wire.DocumentFormat,
                "tokens",
                $Wire.Version,
                $Wire.Identifier,
                $Wire.Key
            )
        }

        if ($opSignal.MergeSignalAndVerifySuccess($documentSignal) -and $documentSignal.Result) {
            $Wire.ContentDynamic = $documentSignal.Result
            $Wire.ContentString = ($documentSignal.Result | ConvertTo-Json -Depth 10)
        }

        return $opSignal
    }

    [void] AddOrReplaceOutput($Feedback, $ResultOutput) {
        $item = $Feedback.WireOutputDictionary | Where-Object { $_.Key -eq $ResultOutput.Key }

        if (-not $item) {
            $Feedback.WireOutputDictionary += $ResultOutput
        } elseif ($item.Content -ne $ResultOutput.Content) {
            $item.Content = $ResultOutput.Content
        }
    }

    [object] LoadItemLeadContent($Proposal, $Feedback, $Wire, [bool]$Reload = $false) {
        $opSignal = [Signal]::Start() | Select-Object -Last 1

        if ($Wire.LeadWireIdentifier) {
            $opSignal.Result = ($Proposal.GetWires() | Where-Object { $_.Identifier -eq $Wire.LeadWireIdentifier -and $_.CatalogService -eq $Wire.CatalogService })[0]
            if (-not $opSignal.Result) {
                $opSignal.Result = ($Proposal.GetWires() | Where-Object { $_.Identifier -eq $Wire.LeadWireIdentifier })[0]
            }

            if (-not $opSignal.Result) {
                $opSignal.LogCritical("Missing Lead Wire: $($Wire.LeadWireIdentifier)")
            } else {
                $opSignal.MergeSignal($this.LoadItem($Proposal, $Feedback, $opSignal.Result, $Reload))
            }
        }

        return $opSignal
    }

    [object] LoadItemJacketContent($Proposal, $Feedback, $Wire, [bool]$Reload = $false) {
        $opSignal = [Signal]::Start() | Select-Object -Last 1

        if ($Wire.MergeJacket -and $Wire.JacketIdentifier) {
            $opSignal.Result = ($Proposal.GetWires() | Where-Object { $_.Identifier -eq $Wire.JacketIdentifier -and $_.CatalogService -eq $Wire.CatalogService })[0]
            if (-not $opSignal.Result) {
                $opSignal.Result = ($Proposal.GetWires() | Where-Object { $_.Identifier -eq $Wire.JacketIdentifier })[0]
            }

            if (-not $opSignal.Result) {
                $opSignal.LogCritical("Missing Jacket Wire: $($Wire.JacketIdentifier)")
            } else {
                $opSignal.MergeSignal($this.LoadItem($Proposal, $Feedback, $opSignal.Result, $Reload))
            }
        }

        return $opSignal
    }

    [object] LoadItemGroundContent($Proposal, $Feedback, $Wire, [bool]$Reload = $false) {
        $opSignal = [Signal]::Start() | Select-Object -Last 1

        if ($Wire.GroundWireIdentifier) {
            $opSignal.Result = ($Proposal.GetWires() | Where-Object { ($_.Version -eq $Wire.GroundWireIdentifier -or $_.Identifier -eq $Wire.GroundWireIdentifier) -and $_.CatalogService -eq $Wire.CatalogService })[0]
            if (-not $opSignal.Result) {
                $opSignal.Result = ($Proposal.GetWires() | Where-Object { $_.Identifier -eq $Wire.GroundWireIdentifier -or $_.Version -eq $Wire.GroundWireIdentifier })[0]
            }

            if (-not $opSignal.Result) {
                $opSignal.LogCritical("Missing Ground Wire: $($Wire.GroundWireIdentifier)")
            } else {
                $opSignal.MergeSignal($this.LoadItem($Proposal, $Feedback, $opSignal.Result, $Reload))
            }
        }

        return $opSignal
    }

    [object] LoadItemCrossContent($Proposal, $Feedback, $Wire, [bool]$Reload = $false) {
        $opSignal = [Signal]::Start() | Select-Object -Last 1

        if ($Wire.CrossWireIdentifier) {
            $opSignal.Result = ($Proposal.GetWires() | Where-Object { $_.Identifier -eq $Wire.CrossWireIdentifier })[0]

            if ($opSignal.Result) {
                $opSignal.MergeSignal($this.LoadItem($Proposal, $Feedback, $opSignal.Result, $Reload))
            }
        }

        return $opSignal
    }

    [object] CondenseWires($Proposal, $Feedback, $LeadWire, $CircuitWire, [bool]$Force, [bool]$MergeOnly, $Token = $null, $LeadNestPath = $null) {
        $opSignal = [Signal]::Start() | Select-Object -Last 1

        $mergeProposal = [PSCustomObject]@{
            LeadWire       = $LeadWire.ContentDynamic
            CircuitWire    = $CircuitWire.ContentDynamic
            LeadNestPath   = $LeadNestPath
            PerformMergeOnly = $MergeOnly
        }

        $mergeSignal = $this.Conductor.MappedCondenserAdapter.MergeCondenser.Invoke("", $mergeProposal)

        if ($mergeSignal.Success) {
            $opSignal.Result = $mergeSignal.Result
            $CircuitWire.CondensedDynamic = $opSignal.Result.Result
        }

        return $opSignal
    }

    [object] LoadItem($Proposal, $Feedback, $Wire, $WireMergeType = "Unspecified", [bool]$Reload = $false, [int]$LoadLevel = 0, [int]$AutoRunConductionLevel = -1) {
        $opSignal = [Signal]::Start($Feedback) | Select-Object -Last 1

        if ($Reload) {
            $loadResult = $this.LoadItemContent($Wire, $Reload)
            if (-not $opSignal.MergeSignalAndVerifySuccess($loadResult)) {
                return $opSignal
            }
        }

        return $opSignal
    }

    static [object] GetProposal($GetWires, $Wire, $WireMergeType = "Unspecified", [bool]$Reload = $false, [int]$LoadLevel = 0, [int]$AutoRunConductionLevel = -1) {
        return [PSCustomObject]@{
            Wire                  = $Wire
            WireMergeType         = $WireMergeType
            Reload                = $Reload
            LoadLevel             = $LoadLevel
            AutoRunConductionLevel = $AutoRunConductionLevel
            GetWires              = $GetWires
        }
    }
}
