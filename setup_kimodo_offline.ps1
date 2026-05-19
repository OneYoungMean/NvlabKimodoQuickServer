param(
    [switch]$Background
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$tag = "[setup_kimodo_offline.ps1]"
$buildEnvPs1 = Join-Path $scriptDir "buildenv.ps1"
$cloneModelPs1 = Join-Path $scriptDir "models\clonemodel_async.ps1"

if (-not (Test-Path -LiteralPath $buildEnvPs1)) { throw "[ERROR]$tag Missing buildenv script: $buildEnvPs1" }
if (-not (Test-Path -LiteralPath $cloneModelPs1)) { throw "[ERROR]$tag Missing model clone script: $cloneModelPs1" }

if ($Background) {
    $env:KIMODO_SETUP_BG = "1"
}

$setupSentinel = Join-Path $scriptDir ".kimodo_offline_setup_complete"
$venvPy = Join-Path $scriptDir ".venv\Scripts\python.exe"
$reqCheckpoint = Join-Path $scriptDir "models\Kimodo-SOMA-RP-v1\model.safetensors"
$reqMetaDir = Join-Path $scriptDir "models\Meta-Llama-3-8B-Instruct"
$reqNf4 = Join-Path $scriptDir "models\KIMODO-Meta3_llm2vec_NF4\model.safetensors"

Write-Output "[STEP]$tag Starting parallel setup stages: buildenv + clonemodel..."
$buildLog = Join-Path $scriptDir "buildenv_stage.log"
$cloneLog = Join-Path $scriptDir "clonemodel_stage.log"
if (Test-Path -LiteralPath $buildLog) { Remove-Item -LiteralPath $buildLog -Force }
if (Test-Path -LiteralPath $cloneLog) { Remove-Item -LiteralPath $cloneLog -Force }

$buildProc = Start-Process -FilePath "powershell.exe" -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $buildEnvPs1, "-RootDir", $scriptDir
) -RedirectStandardOutput $buildLog -RedirectStandardError $buildLog -PassThru -WindowStyle Hidden

$cloneProc = Start-Process -FilePath "powershell.exe" -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $cloneModelPs1, "-ModelsDir", (Join-Path $scriptDir "models")
) -RedirectStandardOutput $cloneLog -RedirectStandardError $cloneLog -PassThru -WindowStyle Hidden

Wait-Process -Id $buildProc.Id, $cloneProc.Id

if (Test-Path -LiteralPath $buildLog) { Get-Content -LiteralPath $buildLog | ForEach-Object { Write-Output $_ } }
if (Test-Path -LiteralPath $cloneLog) { Get-Content -LiteralPath $cloneLog | ForEach-Object { Write-Output $_ } }

if ($buildProc.ExitCode -ne 0) { throw "[ERROR]$tag buildenv.ps1 failed with exit code $($buildProc.ExitCode). Log: $buildLog" }
if ($cloneProc.ExitCode -ne 0) { throw "[ERROR]$tag clonemodel_async.ps1 failed with exit code $($cloneProc.ExitCode). Log: $cloneLog" }

if (-not (Test-Path -LiteralPath $venvPy)) { throw "[ERROR]$tag Missing venv python after setup: $venvPy" }
if (-not (Test-Path -LiteralPath $reqCheckpoint)) { throw "[ERROR]$tag Missing checkpoint: $reqCheckpoint" }

$hasMeta = (Test-Path -LiteralPath (Join-Path $reqMetaDir "model.safetensors.index.json")) -or (Test-Path -LiteralPath (Join-Path $reqMetaDir "model.safetensors"))
if ((-not $hasMeta) -and (-not (Test-Path -LiteralPath $reqNf4))) {
    throw "[ERROR]$tag Missing text encoder model. Need one of: $reqMetaDir or $reqNf4"
}

"setup_time=$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))`r`nvenv_py=$venvPy`r`nroot_dir=$scriptDir" | Set-Content -LiteralPath $setupSentinel -Encoding ASCII
Write-Output "[OK]$tag Offline setup staged."
Write-Output "[INFO]$tag ROOT_DIR=$scriptDir"
Write-Output "[INFO]$tag VENV_PY=$venvPy"
Write-Output "[INFO]$tag SENTINEL=$setupSentinel"
exit 0
