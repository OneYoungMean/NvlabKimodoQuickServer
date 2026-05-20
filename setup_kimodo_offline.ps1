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
    & $PythonExe -c "import numpy; import kimodo; import huggingface_hub; import safetensors" *> $null
    return ($LASTEXITCODE -eq 0)
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
    Write-Output "[STEP]$tag Starting parallel setup stages: buildenv + clonemodel..."

    $jobs = @()
    $jobs += Start-Job -Name "buildenv.ps1" -ScriptBlock {
        param($scriptPath, $root)
        $ErrorActionPreference = "Stop"
        try {
            & $scriptPath -RootDir $root 2>&1 | ForEach-Object { "[buildenv.ps1] $_" }
            if ($LASTEXITCODE -ne 0) {
                throw "ExitCode=$LASTEXITCODE"
            }
            [pscustomobject]@{ __stage = "buildenv"; __ok = $true }
        }
        catch {
            [pscustomobject]@{ __stage = "buildenv"; __ok = $false; __error = ($_ | Out-String) }
        }
    } -ArgumentList $buildEnvPs1, $scriptDir

    $jobs += Start-Job -Name "clonemodel_async.ps1" -ScriptBlock {
        param($scriptPath, $modelsDir)
        $ErrorActionPreference = "Stop"
        try {
            & $scriptPath -ModelsDir $modelsDir 2>&1 | ForEach-Object { "[clonemodel_async.ps1] $_" }
            if ($LASTEXITCODE -ne 0) {
                throw "ExitCode=$LASTEXITCODE"
            }
            [pscustomobject]@{ __stage = "clonemodel"; __ok = $true }
        }
        catch {
            [pscustomobject]@{ __stage = "clonemodel"; __ok = $false; __error = ($_ | Out-String) }
        }
    } -ArgumentList $cloneModelPs1, (Join-Path $scriptDir "models")

    $results = @{}
    foreach ($job in $jobs) {
        Wait-Job -Job $job | Out-Null
        $items = Receive-Job -Job $job
        foreach ($item in $items) {
            if ($item -is [string]) {
                Write-Output $item
                continue
            }
            if ($item.PSObject.Properties.Match("__stage").Count -gt 0) {
                $results[$item.__stage] = $item
                continue
            }
            Write-Output $item
        }
    }
    foreach ($job in $jobs) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }

    if ((-not $results.ContainsKey("buildenv")) -or (-not $results["buildenv"].__ok)) {
        $err = if ($results.ContainsKey("buildenv")) { $results["buildenv"].__error } else { "missing job result" }
        throw "[ERROR]$tag buildenv.ps1 failed. $err"
    }
    if ((-not $results.ContainsKey("clonemodel")) -or (-not $results["clonemodel"].__ok)) {
        $err = if ($results.ContainsKey("clonemodel")) { $results["clonemodel"].__error } else { "missing job result" }
        throw "[ERROR]$tag clonemodel_async.ps1 failed. $err"
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
