param(
    [string]$Model = "Kimodo-SOMA-RP-v1",
    [string]$KimodoRoot
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$legacyBat = Join-Path $scriptDir "start_kimodo_bridge_offline_legacy.bat"
if (-not (Test-Path -LiteralPath $legacyBat)) {
    throw "[ERROR] Legacy start script not found: $legacyBat"
}

$argsList = @()
if ($Model) {
    $argsList += "--model"
    $argsList += $Model
}
if ($KimodoRoot) {
    $argsList += "--kimodo-root"
    $argsList += $KimodoRoot
}

$quoted = $argsList | ForEach-Object { '"' + $_.Replace('"','\"') + '"' }
$argText = [string]::Join(' ', $quoted)
& cmd.exe /d /c "`"$legacyBat`" $argText"
exit $LASTEXITCODE
