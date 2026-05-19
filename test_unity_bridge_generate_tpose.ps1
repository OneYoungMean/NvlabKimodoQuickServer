param()

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$legacyBat = Join-Path $scriptDir "test_unity_bridge_generate_tpose_legacy.bat"
if (-not (Test-Path -LiteralPath $legacyBat)) {
    throw "[ERROR] Legacy test script not found: $legacyBat"
}

& cmd.exe /d /c "`"$legacyBat`""
exit $LASTEXITCODE
