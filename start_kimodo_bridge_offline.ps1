param(
    [string]$Model = "Kimodo-SOMA-RP-v1",
    [string]$KimodoRoot
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$legacyBat = Join-Path $scriptDir "start_kimodo_bridge_offline_impl.bat"
if (-not (Test-Path -LiteralPath $legacyBat)) {
    throw "[ERROR] Start impl script not found: $legacyBat"
}

$resolvedRoot = $KimodoRoot
if ([string]::IsNullOrWhiteSpace($resolvedRoot)) {
    $resolvedRoot = $scriptDir
}
if (Test-Path -LiteralPath $resolvedRoot) {
    $resolvedRoot = (Resolve-Path -LiteralPath $resolvedRoot).Path
}

$argsList = @()
if ($Model) {
    $argsList += "--model"
    $argsList += $Model
}
$argsList += "--kimodo-root"
$argsList += $resolvedRoot

$quoted = $argsList | ForEach-Object { '"' + $_.Replace('"','\"') + '"' }
$argText = [string]::Join(' ', $quoted)
& cmd.exe /d /c "`"$legacyBat`" $argText"
exit $LASTEXITCODE


