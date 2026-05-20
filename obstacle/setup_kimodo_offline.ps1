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
$sourceRoot = $null
if (Test-Path -LiteralPath (Join-Path $scriptDir "pyproject.toml")) {
    $sourceRoot = $scriptDir
}
elseif (Test-Path -LiteralPath (Join-Path $scriptDir "kimodo\pyproject.toml")) {
    $sourceRoot = Join-Path $scriptDir "kimodo"
}
if ($sourceRoot) {
    $env:PYTHONPATH = $sourceRoot
}

# Preferred pip mirrors for constrained networks.
$pipIndexPrimary = "https://pypi.doubanio.com/simple"
$pipExtraIndexes = @(
    "https://pypi.oystermercury.top/ms",
    "https://gitlab.inria.fr/api/v4/projects/18692/packages/pypi/simple"
)
$env:PIP_INDEX_URL = $pipIndexPrimary
$env:PIP_EXTRA_INDEX_URL = ($pipExtraIndexes -join " ")
Write-Output "[INFO]$tag PIP_INDEX_URL=$($env:PIP_INDEX_URL)"
Write-Output "[INFO]$tag PIP_EXTRA_INDEX_URL=$($env:PIP_EXTRA_INDEX_URL)"

function Test-BuildEnvReady {
    param([string]$PythonExe, [string]$SentinelPath)
    if ((Test-Path -LiteralPath $PythonExe) -and (Test-Path -LiteralPath $SentinelPath)) {
        return $true
    }
    if (-not (Test-Path -LiteralPath $PythonExe)) { return $false }
    $checkScript = @"
import importlib
mods = ["numpy", "kimodo", "huggingface_hub", "safetensors"]
for m in mods:
    importlib.import_module(m)
"@
    $tmp = Join-Path $env:TEMP ("kimodo_buildenv_check_" + [Guid]::NewGuid().ToString("N") + ".py")
    Set-Content -LiteralPath $tmp -Value $checkScript -Encoding ASCII
    try {
        $quotedPy = '"' + $PythonExe.Replace('"','""') + '"'
        $quotedTmp = '"' + $tmp.Replace('"','""') + '"'
        & cmd.exe /d /c "$quotedPy $quotedTmp >nul 2>nul"
        return ($LASTEXITCODE -eq 0)
    }
    finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

$buildEnvReady = Test-BuildEnvReady -PythonExe $venvPy -SentinelPath $setupSentinel
if ($buildEnvReady) {
    Write-Output "[INFO]$tag Buildenv already ready. Skip buildenv stage."
    Write-Output "[STEP]$tag Running setup stages: clonemodel only."
    & $cloneModelPs1 -ModelsDir (Join-Path $scriptDir "models") 2>&1 | ForEach-Object { Write-Output "[clonemodel_async.ps1] $_" }
    if ($LASTEXITCODE -ne 0) {
        throw "[ERROR]$tag clonemodel_async.ps1 failed with exit code $LASTEXITCODE"
    }
}
else {
    Write-Output "[STEP]$tag Running setup stages in single-thread mode: buildenv -> clonemodel."

    & $buildEnvPs1 -RootDir $scriptDir 2>&1 | ForEach-Object { Write-Output "[buildenv.ps1] $_" }
    if ($LASTEXITCODE -ne 0) {
        throw "[ERROR]$tag buildenv.ps1 failed with exit code $LASTEXITCODE"
    }

    & $cloneModelPs1 -ModelsDir (Join-Path $scriptDir "models") 2>&1 | ForEach-Object { Write-Output "[clonemodel_async.ps1] $_" }
    if ($LASTEXITCODE -ne 0) {
        throw "[ERROR]$tag clonemodel_async.ps1 failed with exit code $LASTEXITCODE"
    }
}

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
