#TODO: Move this script to the test folder
function Run-ResolvePathTests {
    param (
        [string]$TestFilePath = ".\resolve_path_test_cases.json"
    )

    if (-not (Test-Path $TestFilePath)) {
        Write-Error "❌ Test file not found: $TestFilePath"
        return
    }

    $json = Get-Content $TestFilePath -Raw | ConvertFrom-Json

    foreach ($case in $json) {
        Write-Host "🧪 $($case.Description)" -ForegroundColor Cyan

        # Create a signal for tracking
        $signal = Resolve-PathFromDictionary -Dictionary $case.Input -Path $case.Path

        $actual = $signal.GetResult()
        $expected = $case.Expected

        if ($actual -eq $expected) {
            Write-Host "✅ PASSED: Expected = '$expected'" -ForegroundColor Green
        } else {
            Write-Host "❌ FAILED: Got = '$actual', Expected = '$expected'" -ForegroundColor Red
            if ($signal.Entries) {
                Write-Host "   ➤ Trace:"
                foreach ($entry in $signal.Entries) {
                    Write-Host "     • [$($entry.Level)] $($entry.Message)"
                }
            }
        }

        Write-Host ""
    }
}

