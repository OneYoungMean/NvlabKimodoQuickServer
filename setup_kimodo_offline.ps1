param(
    [switch]$Background
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$legacyBat = Join-Path $scriptDir "setup_kimodo_offline_legacy.bat"
if (-not (Test-Path -LiteralPath $legacyBat)) {
    throw "[ERROR] Legacy setup script not found: $legacyBat"
}

if ($Background) {
    $env:KIMODO_SETUP_BG = "1"
}

& cmd.exe /d /c "`"$legacyBat`""
exit $LASTEXITCODE
