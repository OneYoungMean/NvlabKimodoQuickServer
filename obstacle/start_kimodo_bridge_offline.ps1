param(
    [string]$Model = "Kimodo-SOMA-RP-v1",
    [string]$KimodoRoot,
    [string]$LogPath
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
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = Join-Path $resolvedRoot "start_kimodo_bridge_offline.log"
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
$cmdLine = "`"$legacyBat`" $argText"

if (-not (Test-Path -LiteralPath (Split-Path -Parent $LogPath))) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $LogPath) -Force | Out-Null
}
Write-Output ("[INFO] start log: " + $LogPath)
$wrappedCmdLine = "$cmdLine 2>&1"
$activeLogPath = $LogPath
try {
    & cmd.exe /d /c $wrappedCmdLine | Tee-Object -FilePath $activeLogPath -Append
    $exitCode = $LASTEXITCODE
}
catch {
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $fallback = Join-Path (Split-Path -Parent $LogPath) ("start_kimodo_bridge_offline_" + $ts + ".log")
    Write-Warning ("log file is busy, fallback to: " + $fallback)
    $activeLogPath = $fallback
    & cmd.exe /d /c $wrappedCmdLine | Tee-Object -FilePath $activeLogPath
    $exitCode = $LASTEXITCODE
}
exit $exitCode


