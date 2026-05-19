param(
    [string]$RootDir = (Split-Path -Parent $MyInvocation.MyCommand.Path)
)

$ErrorActionPreference = "Stop"
$tag = "[buildenv.ps1]"

if (-not (Test-Path -LiteralPath $RootDir)) {
    throw "[ERROR]$tag Invalid RootDir: $RootDir"
}

$legacyBat = Join-Path $RootDir "setup_kimodo_offline_legacy.bat"
if (-not (Test-Path -LiteralPath $legacyBat)) {
    throw "[ERROR]$tag Missing legacy setup script: $legacyBat"
}

Write-Output "[STEP]$tag Running buildenv stage via legacy setup in buildenv-only mode..."
$env:KIMODO_BUILDENV_ONLY = "1"
try {
    & cmd.exe /d /c "`"$legacyBat`""
    if ($LASTEXITCODE -ne 0) {
        throw "[ERROR]$tag Buildenv stage failed with exit code: $LASTEXITCODE"
    }
}
finally {
    Remove-Item Env:KIMODO_BUILDENV_ONLY -ErrorAction SilentlyContinue
}

Write-Output "[OK]$tag Buildenv stage completed."
exit 0
