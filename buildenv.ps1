param(
    [string]$RootDir = (Split-Path -Parent $MyInvocation.MyCommand.Path)
)

$ErrorActionPreference = "Stop"
$tag = "[buildenv.ps1]"

if (-not (Test-Path -LiteralPath $RootDir)) {
    throw "[ERROR]$tag Invalid RootDir: $RootDir"
}

$legacyBat = Join-Path $RootDir "setup_kimodo_offline_impl.bat"
if (-not (Test-Path -LiteralPath $legacyBat)) {
    throw "[ERROR]$tag Missing setup impl script: $legacyBat"
}

Write-Output "[STEP]$tag Running buildenv stage via setup impl in buildenv-only mode..."
$env:KIMODO_BUILDENV_ONLY = "1"
try {
    & cmd.exe /d /c "cd /d `"$RootDir`" && `"$legacyBat`""
    if ($LASTEXITCODE -ne 0) {
        throw "[ERROR]$tag Buildenv stage failed with exit code: $LASTEXITCODE"
    }
}
finally {
    Remove-Item Env:KIMODO_BUILDENV_ONLY -ErrorAction SilentlyContinue
}

Write-Output "[OK]$tag Buildenv stage completed."
exit 0


