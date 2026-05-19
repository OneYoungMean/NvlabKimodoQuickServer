param(
    [string]$ModelsDir = (Split-Path -Parent $MyInvocation.MyCommand.Path)
)

$ErrorActionPreference = "Stop"

function Ensure-GitLfs {
    git --version *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "[ERROR] git is not installed or not on PATH."
    }
    git lfs version *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "[ERROR] git lfs is not installed or not on PATH."
    }
    git lfs install --skip-repo *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "[ERROR] git lfs install failed."
    }
}

function Start-CloneJob {
    param(
        [string]$RepoUrl,
        [string]$DestDir,
        [string[]]$RequiredFiles
    )

    Start-Job -ScriptBlock {
        param($RepoUrl, $DestDir, $RequiredFiles)
        $ErrorActionPreference = "Stop"

        $allReady = $true
        foreach ($rel in $RequiredFiles) {
            $fp = Join-Path $DestDir $rel
            if (-not (Test-Path -LiteralPath $fp)) {
                $allReady = $false
                break
            }
        }
        if ($allReady) {
            Write-Output ("[INFO] Skip existing model: " + $DestDir)
            return
        }

        if (-not (Test-Path -LiteralPath $DestDir)) {
            Write-Output ("[STEP] Cloning " + $RepoUrl)
            & git clone $RepoUrl $DestDir
            if ($LASTEXITCODE -ne 0) {
                throw ("git clone failed: " + $RepoUrl)
            }
        }
        else {
            if (-not (Test-Path -LiteralPath (Join-Path $DestDir ".git"))) {
                throw ("[ERROR] Destination exists but is not a git repo: " + $DestDir)
            }
            Write-Output ("[STEP] Updating existing repo: " + $DestDir)
            & git -C $DestDir pull
            if ($LASTEXITCODE -ne 0) {
                throw ("git pull failed: " + $DestDir)
            }
        }

        & git -C $DestDir lfs pull
        if ($LASTEXITCODE -ne 0) {
            throw ("git lfs pull failed: " + $DestDir)
        }

        foreach ($rel in $RequiredFiles) {
            $fp = Join-Path $DestDir $rel
            if (-not (Test-Path -LiteralPath $fp)) {
                throw ("[ERROR] Missing " + $rel + " after clone: " + $DestDir)
            }
        }

        Write-Output ("[OK] Ready: " + $DestDir)
    } -ArgumentList $RepoUrl, $DestDir, $RequiredFiles
}

if (-not (Test-Path -LiteralPath $ModelsDir)) {
    New-Item -ItemType Directory -Path $ModelsDir | Out-Null
}

Ensure-GitLfs

$jobs = @()
$jobs += Start-CloneJob -RepoUrl "https://www.modelscope.cn/nv-community/Kimodo-SOMA-RP-v1.1.git" -DestDir (Join-Path $ModelsDir "Kimodo-SOMA-RP-v1") -RequiredFiles @("model.safetensors")
$jobs += Start-CloneJob -RepoUrl "https://www.modelscope.cn/oneyoungmean/KIMODO-Meta3_llm2vec_NF4.git" -DestDir (Join-Path $ModelsDir "KIMODO-Meta3_llm2vec_NF4") -RequiredFiles @("model.safetensors")

$failed = $false
foreach ($job in $jobs) {
    Wait-Job -Job $job | Out-Null
    try {
        Receive-Job -Job $job -ErrorAction Stop
    }
    catch {
        Write-Error $_
        $failed = $true
    }
    if ($job.State -ne "Completed") {
        $failed = $true
    }
}

foreach ($job in $jobs) {
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
}

if ($failed) {
    throw "[ERROR] Async model clone failed."
}

Write-Output "[OK] Model clone complete."
exit 0
