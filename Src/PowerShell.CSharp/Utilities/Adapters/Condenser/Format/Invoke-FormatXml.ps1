function Invoke-FormatXml {
    param (
        [Parameter(Mandatory)][string]$Path,
        [object]$Plan
    )

    $opSignal = [Signal]::Start("Invoke-TokenFormatterJson") | Select-Object -Last 1

    function ConvertFrom-Xml {
        param (
            [Parameter(Mandatory)]
            [System.Xml.XmlNode]$Node
        )

        # If the node is a simple text node
        if ($Node.ChildNodes.Count -eq 1 -and $Node.FirstChild.NodeType -eq 'Text') {
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

    try {
        $xmlDocument = New-Object System.Xml.XmlDocument
        $xmlDocument.LoadXml(($Path -replace '^\uFEFF', ''))

        $opSignal.SetResult($xmlDocument)

        $opSignal.LogInformation("✅ Xml Document Created from Path")
    }
    catch {
        $opSignal.LogCritical("🔥 Exception in Invoke-FormatXml: $_", $null, $_)
    }

    return $opSignal
}
