function Invoke-TransformSelect {
    param (
        [Parameter(Mandatory)][object]$Source,
        [string]$SourceFormat,
        [string]$SourcePath,
        [string]$SourceInnerPath,
        [bool]$SourceHtmlDecode
    )

    $opSignal = [Signal]::Start("Invoke-TransformSelect") | Select-Object -Last 1

    function ConvertFrom-Xml {
        param (
            [Parameter(Mandatory)]
            [System.Xml.XmlNode]$Node
        )

        # If the node is a simple text node
        if ($Node.ChildNodes.Count -eq 1 -and $Node.FirstChild.NodeType -eq 'Text') {
            return $Node.InnerText
        }

        # If the node contains only text or CDATA, return its contents directly
        if (
            $Node.ChildNodes.Count -eq 1 -and
            $Node.FirstChild.NodeType -in @('Text', 'CDATA')
        ) {
            return $Node.InnerText
        }

        $hash = @{}

        # Attributes (optional but useful)
        foreach ($attr in $Node.Attributes) {
            $hash["@${($attr.Name)}"] = $attr.Value
        }

        foreach ($child in $Node.ChildNodes | Where-Object NodeType -eq 'Element') {
            $value = ConvertFrom-Xml -Node $child

            if ($hash.ContainsKey($child.Name)) {
                # Promote to array
                if ($hash[$child.Name] -isnot [System.Collections.IList]) {
                    $hash[$child.Name] = @($hash[$child.Name])
                }
                $hash[$child.Name] += $value
            }
            else {
                $hash[$child.Name] = $value
            }
        }

        return [pscustomobject]$hash
    }

    
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

        function Split-VirtualPathSegments {
            param([Parameter(Mandatory)][string]$Text)

            # Split on '.' but NOT inside [...]
            $segments = New-Object System.Collections.Generic.List[string]
            $sb = New-Object System.Text.StringBuilder
            $depth = 0

            foreach ($ch in $Text.ToCharArray()) {
                switch ($ch) {
                    '[' { $depth++; [void]$sb.Append($ch) }
                    ']' { if ($depth -gt 0) { $depth-- }; [void]$sb.Append($ch) }
                    '.' {
                        if ($depth -eq 0) {
                            $seg = $sb.ToString().Trim()
                            if ($seg) { $segments.Add($seg) }
                            [void]$sb.Clear()
                        }
                        else {
                            [void]$sb.Append($ch)
                        }
                    }
                    default { [void]$sb.Append($ch) }
                }
            }

            $tail = $sb.ToString().Trim()
            if ($tail) { $segments.Add($tail) }

            return $segments.ToArray()
        }

        try {
            if ([string]::IsNullOrWhiteSpace($VirtualPath)) {
                $opSignal.LogWarning("VirtualPath is empty. Nothing to convert.")
                return $opSignal
            }

            $segments = Split-VirtualPathSegments -Text $VirtualPath
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

                    # This is turned off because elements are broken up by periods and attributes are looked up in brackets
                    # - If predicate key starts with '@' => attribute match (@Name='x')
                    # - Else => child element match (Name='x')
                    if ($true -or $attr.StartsWith('@')) {
                        #$a = $attr.Substring(1)
                        $a = $attr.Substring(0)
                        if ([string]::IsNullOrWhiteSpace($a)) {
                            throw "Invalid attribute predicate in segment '$seg': [$predicate]"
                        }
                        $xpathNode = "$xpathNode[@$a=$xpathLiteral]"
                    }
                    else {
                        $xpathNode = "$xpathNode[$attr=$xpathLiteral]"                        
                    }
                }

                $xpathParts += $xpathNode
            }

            $result = ($xpathParts -join '/')
            if (-not $result.StartsWith('//')) { $result = '//' + $result }
            $opSignal.SetResult($result)
        }
        catch {
            $opSignal.LogCritical("🔥 Exception during Convert-VirtualPathToXPath: $_", $null, $_)
        }

        return $opSignal
    }


    try {
        $result = $null
        switch ($SourceFormat) {
            'Json' {
                if ($SourcePath) {
                    $selectedSignal = Resolve-PathFromDictionary -Dictionary $Source -Path $SourcePath | Select-Object -Last 1
                    if ($opSignal.MergeSignalAndVerifyFailure($selectedSignal)) {
                        return $opSignal
                    }

                    $result = $selectedSignal.GetResult()
                    if ($null -eq $result) { 
                        $opSignal.LogCritical("🔥 Path returned no result: $SourcePath") 
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

                # 1) First hop (optional)
                if ($SourcePath) {
                    $xpathSignal = Convert-VirtualPathToXPath -VirtualPath $SourcePath
                    if ($xpathSignal.HasResult()) {
                        $SourcePath = $xpathSignal.GetResult()
                    }

                    $nodes = $xmlDocument.SelectNodes($SourcePath)

                    if (-not $nodes -or $nodes.Count -eq 0) {
                        $opSignal.LogInformation("🔥 Path returned no result: $SourcePath")
                        return $opSignal
                    }

                    if ($nodes.Count -eq 1) {
                        $result = ConvertFrom-Xml -Node $nodes[0]
                    }
                    else {
                        # Multiple nodes → concatenate; NOTE: without wrapping this is not a valid XML document
                        $result = ($nodes | ForEach-Object { ConvertFrom-Xml -Node $_ }) 
                    }

                    $result = $result -is [string] -and $SourceHtmlDecode ? [System.Net.WebUtility]::HtmlDecode($result) : $result
                }

                <#
                if ($SourceHtmlDecode) {
                    $result = [System.Net.WebUtility]::HtmlDecode($result)
                }
                #>
                break
            }
            default {
                $result = $Source -is [string] -and $SourceHtmlDecode ? [System.Net.WebUtility]::HtmlDecode($Source) : $Source
            }
        }

        $opSignal.SetResult($result)
        $opSignal.LogInformation("✅ Transform from Select Path Complete")
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Invoke-TransformSelect: $_", $null, $_)
    }

    return $opSignal
}
