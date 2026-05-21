param(
    [string]$ModelsDir = (Split-Path -Parent $MyInvocation.MyCommand.Path)
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cloneBat = Join-Path $scriptDir "clonemodel.bat"

if (-not (Test-Path -LiteralPath $ModelsDir)) {
    New-Item -ItemType Directory -Path $ModelsDir -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $cloneBat)) {
    throw "[ERROR] Missing clone script: $cloneBat"
}

Write-Output "[STEP][clonemodel_async.ps1] Delegating model clone to clonemodel.bat (single-thread)."

Push-Location $ModelsDir
try {
    & cmd.exe /d /c "`"$cloneBat`""
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

if ($exitCode -ne 0) {
    throw "[ERROR] clonemodel.bat failed with exit code $exitCode"
}

Write-Output "[OK][clonemodel_async.ps1] Model clone complete."
exit 0

