param()

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$implBat = Join-Path $scriptDir "test_unity_bridge_generate_tpose_with_log_impl.bat"
if (-not (Test-Path -LiteralPath $implBat)) {
    throw "[ERROR] Test with log impl script not found: $implBat"
}

& cmd.exe /d /c "`"$implBat`""
exit $LASTEXITCODE
