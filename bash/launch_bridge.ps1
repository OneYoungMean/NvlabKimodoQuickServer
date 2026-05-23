param(
    [Parameter(Mandatory = $true)][string]$PythonPath,
    [Parameter(Mandatory = $true)][string]$RootDir,
    [Parameter(Mandatory = $true)][string]$ModelName,
    [Parameter(Mandatory = $true)][string]$WindowStyle,
    [Parameter(Mandatory = $true)][string]$BridgeLogPath,
    [Parameter(Mandatory = $true)][string]$BridgeMessageLogPath,
    [Parameter(Mandatory = $true)][string]$PidFile,
    [Parameter(Mandatory = $true)][string]$OutputMode
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($WindowStyle)) {
    $WindowStyle = "Hidden"
}

$args = @(
    "-u",
    "-m",
    "kimodo.bridge.bridge_server",
    "--model",
    $ModelName,
    "--kimodo-root",
    $RootDir
)

$env:KIMODO_BRIDGE_LOG = $BridgeLogPath
$workingDir = Split-Path -Parent $PidFile
if (-not [string]::IsNullOrWhiteSpace($workingDir)) {
    New-Item -ItemType Directory -Path $workingDir -Force | Out-Null
}

$startInfo = @{
    FilePath = $PythonPath
    ArgumentList = $args
    WorkingDirectory = $RootDir
    WindowStyle = $WindowStyle
    PassThru = $true
}

if ($OutputMode -ieq "file") {
    $startInfo.RedirectStandardOutput = $BridgeLogPath
    $startInfo.RedirectStandardError = $BridgeMessageLogPath
}

$process = Start-Process @startInfo
$tmpPidFile = "$PidFile.tmp"
[System.IO.File]::WriteAllText($tmpPidFile, "$($process.Id)`n", (New-Object System.Text.UTF8Encoding($false)))
Move-Item -LiteralPath $tmpPidFile -Destination $PidFile -Force
