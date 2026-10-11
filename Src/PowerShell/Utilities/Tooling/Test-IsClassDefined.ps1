# =============================================================================
# 🧠 SovereignTrust Diagnostic Utility: Test-IsClassDefined
# =============================================================================
# Checks whether a PowerShell class is defined or resolvable from the current
# application domain. Returns a Signal with embedded result and diagnostics.
#
# ✅ Use this in dynamic loading, plugin detection, or conditional execution
# 📦 Supports namespace-style resolution from assemblies and runtime classes
# =============================================================================

function Test-IsClassDefined {
    param (
        [Parameter(Mandatory)]
        [string]$ClassName
    )

    $opSignal = [Signal]::Start("Test-IsClassDefined:$ClassName") | Select-Object -Last 1

    function Test-IsFunctionDefined {
        param (
            [Parameter(Mandatory)]
            [string]$FunctionName
        )

        return $null -ne (Get-Command `
            -Name $FunctionName `
            -CommandType Function `
            -ErrorAction SilentlyContinue `
        | Select-Object -First 1)
    }

    try {
        $resolverFunctionName = "Resolve-$ClassName"

        # ░▒▓█ TYPE DIRECT QUERY █▓▒░
        $type = [Type]::GetType($ClassName, $false)
        if ($type) {
            if (Test-IsFunctionDefined -FunctionName $resolverFunctionName) {
                $opSignal.LogVerbose("✅ Class and resolver function found: $ClassName, $resolverFunctionName")
                $opSignal.SetResult($true)
            }
            else {
                $opSignal.LogWarning("Class found but resolver function was not found: $resolverFunctionName")
            }
            return $opSignal
        }

#        $types = [AppDomain]::CurrentDomain.GetAssemblies() 
        
        # ░▒▓█ ASSEMBLY SCAN █▓▒░
        $opSignal.LogVerbose("🔍 Scanning assemblies for class: $ClassName")
        $type = [AppDomain]::CurrentDomain.GetAssemblies() |
            ForEach-Object { $_.GetType($ClassName, $false) } |
            Where-Object { $_ -ne $null } |
            Select-Object -First 1

        if ($type -and (Test-IsFunctionDefined -FunctionName $resolverFunctionName)) {
            $opSignal.LogVerbose("✅ Class found in assembly with resolver function '$resolverFunctionName': $($type.Assembly.FullName)")
            $opSignal.SetResult($type)
        }
        elseif ($type) {
            $opSignal.LogWarning("Class found but resolver function was not found: $resolverFunctionName")
        }
        else {
            $opSignal.LogWarning("Class not found: $ClassName")
            #$opSignal.SetResult($false)
        }
    }
    catch {
        $opSignal.LogCritical("🔥 Exception while checking class: $($_.Exception.Message)", $null, $_)
        #$opSignal.SetResult($false)
    }

    return $opSignal
}
