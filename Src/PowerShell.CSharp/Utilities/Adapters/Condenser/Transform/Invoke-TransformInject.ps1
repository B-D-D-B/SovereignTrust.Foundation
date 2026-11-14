function Invoke-TransformInject {
    param (
        [Parameter(Mandatory)][object]$Source,
        [string]$Format,
        [string]$Path,
        [bool]$HtmlEncode,
        [object]$target
    )

    $opSignal = [Signal]::Start("Invoke-TransformInject") | Select-Object -Last 1

    function Convert-VirtualPathToXPath {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$VirtualPath
        )

        $opSignal = [Signal]::Start("Convert-VirtualPathToXPath") | Select-Object -Last 1

        function ConvertTo-XPathLiteral {
            param([Parameter(Mandatory)][string]$Value)

            if ($Value -notlike "*'*") { return "'$Value'" }
            if ($Value -notlike '*"*') { return '"' + $Value + '"' }

            # Contains both ' and " → use concat()
            $parts = @()
            $buf = ""

            foreach ($ch in $Value.ToCharArray()) {
                if ($ch -eq "'") {
                    if ($buf.Length) { $parts += "'$buf'"; $buf = "" }
                    $parts += '"''"'   # literal single quote
                }
                elseif ($ch -eq '"') {
                    if ($buf.Length) { $parts += "'$buf'"; $buf = "" }
                    $parts += ("'" + '"' + "'")   # literal double quote for XPath: '"'
                }
                else {
                    $buf += $ch
                }
            }

            if ($buf.Length) { $parts += "'$buf'" }
            return "concat(" + ($parts -join ",") + ")"
        }

        try {
            if ([string]::IsNullOrWhiteSpace($VirtualPath)) {
                $opSignal.LogWarning("VirtualPath is empty. Nothing to convert.")
                return $opSignal
            }

            $segments = $VirtualPath -split '\.'
            $xpathParts = @()

            foreach ($seg in $segments) {

                # Reject ordinal-based segments
                if ($seg -match '^\d+$') {
                    throw "Ordinal-based VirtualPath segments are not supported: '$seg'. Use [Key=Value] predicates only."
                }

                if ($seg -notmatch '^\s*([^\[]+)\s*((?:\[[^\]]*\])*)\s*$') {
                    throw "Unrecognized VirtualPath segment format: '$seg'"
                }

                $node = $matches[1].Trim()
                $predBlock = $matches[2]

                if ([string]::IsNullOrWhiteSpace($node)) {
                    throw "Invalid VirtualPath segment '$seg' (empty node name)."
                }

                $xpathNode = $node

                foreach ($m in [regex]::Matches($predBlock, '\[([^\]]*)\]')) {
                    $predicate = $m.Groups[1].Value.Trim()

                    # Reject ordinal predicates
                    if ($predicate -match '^\d+$') {
                        throw "Ordinal predicates are not supported: [$predicate]. Use [Key=Value] predicates only."
                    }

                    $eq = $predicate.IndexOf('=')
                    if ($eq -lt 1) {
                        throw "Unsupported predicate format: [$predicate]. Expected [Key=Value] or [Key=""Value""]"
                    }

                    $attr = $predicate.Substring(0, $eq).Trim()
                    $valRaw = $predicate.Substring($eq + 1).Trim()

                    if ([string]::IsNullOrWhiteSpace($attr)) {
                        throw "Invalid predicate attribute in segment '$seg': [$predicate]"
                    }

                    # Strip one layer of wrapping quotes if present
                    if (
                        ($valRaw.Length -ge 2) -and
                        (
                            ($valRaw.StartsWith('"') -and $valRaw.EndsWith('"')) -or
                            ($valRaw.StartsWith("'") -and $valRaw.EndsWith("'"))
                        )
                    ) {
                        $val = $valRaw.Substring(1, $valRaw.Length - 2)
                    }
                    else {
                        $val = $valRaw
                    }

                    $xpathLiteral = ConvertTo-XPathLiteral -Value $val
                    $xpathNode = "$xpathNode[@$attr=$xpathLiteral]"
                }

                $xpathParts += $xpathNode
            }

            $result = '//' + ($xpathParts -join '/')
            $opSignal.SetResult($result)
            $opSignal.MarkSuccess()
        }
        catch {
            $opSignal.LogCritical("🔥 Exception during Convert-VirtualPathToXPath: $_", $null, $_)
        }

        return $opSignal
    }


    try {
        $result = $null
        switch ($Format) {
            'Json' {
                if ($Path) {
                    $InjectedSignal = Resolve-PathFromDictionary -Dictionary $Source -Path $Path | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($InjectedSignal)) {
                        return $opSignal
                    }

                    $result = $InjectedSignal.GetResult()
                    if ($null -eq $result) { 
                        $opSignal.LogCritical("🔥 Path returned no result: $Path") 
                        return $opSignal
                    }
                }
                else {
                    $result = $jsonObject
                }
                break
            }
            'Xml' {
                [xml]$xmlDocument = $Source
                if ($Path) {
                    $Path = Convert-VirtualPathToXPath -VirtualPath $Path
                    $nodes = $xmlDocument.InjectNodes($Path)
                    if (-not $nodes -or $nodes.Count -eq 0) {
                        $opSignal.LogCritical("🔥 Path returned no result: $Path")
                        return $opSignal
                    }

                    if ($nodes.Count -gt 0) {
                        $result = $nodes[0].InnerXml
                    }
                }
                else {
                    $result = $xmlDocument.InnerXml
                }

                if ($HtmlEncode) {
                    $result = [System.Net.WebUtility]::HtmlDecode($result)
                }
                break
            }
            default {
                $result = $HtmlEncode ? [System.Net.WebUtility]::HtmlDecode($Source) : $Source
            }
        }

        $opSignal.SetResult($result)
        $opSignal.LogInformation("✅ Transform from Inject Path Complete")
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Invoke-TransformInject: $_", $null, $_)
    }

    return $opSignal
}
