param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CliArgs
)

$ErrorActionPreference = "Stop"

$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:RootDir = Split-Path -Parent $script:ScriptDir
$script:LogDir = Join-Path $script:RootDir "log"
$script:ModelsDir = Join-Path $script:RootDir "models"
$script:RunDevice = ""
$script:CpuTextEncoder = "gguf"
$script:VenvPy = ""
$script:ModelName = "Kimodo-SOMA-RP-v1"
$script:OutputMode = "console"
$script:LogPath = Join-Path $script:LogDir "download_model.log"
$script:UnlockStale = $false
$script:ForceSync = $false
$script:HighVram = $false
$script:DownloadGguf = "auto"
$script:GgufDecisionReason = "unset"
$script:VramProbeAvailable = "unknown"
$script:VramProbeDeviceCount = "unknown"
$script:VramProbeTorchCuda = "unknown"
$script:VramProbeStatus = "unknown"
$script:TextEncoderDownloadRequired = $true
$script:TextEncoderStateReason = "unset"
$script:VramProbeLogEnabled = $true

$script:Llm2VecNf4RepoUrl = if ($env:KIMODO_LLM2VEC_NF4_REPO_URL) { $env:KIMODO_LLM2VEC_NF4_REPO_URL } else { "https://www.modelscope.cn/oneyoungmean/KIMODO-Meta3_llm2vec_NF4.git" }
$script:Llm2VecNf4RepoUrlFallback = if ($env:KIMODO_LLM2VEC_NF4_REPO_URL_FALLBACK) { $env:KIMODO_LLM2VEC_NF4_REPO_URL_FALLBACK } else { "https://huggingface.co/Aero-Ex/KIMODO-Meta3_llm2vec_NF4" }
$script:GgufRepoUrl = if ($env:KIMODO_GGUF_REPO_URL) { $env:KIMODO_GGUF_REPO_URL } else { "https://www.modelscope.cn/LLM-Research/Meta-Llama-3.1-8B-Instruct-hf-Q4_K_M-GGUF.git" }
$script:GgufRepoUrlFallback = if ($env:KIMODO_GGUF_REPO_URL_FALLBACK) { $env:KIMODO_GGUF_REPO_URL_FALLBACK } else { "https://huggingface.co/Aero-Ex/Meta-Llama-3.1-8B-Instruct-hf-Q4_K_M-GGUF" }
$script:MetaLlamaRepoUrl = if ($env:KIMODO_META_LLAMA_REPO_URL) { $env:KIMODO_META_LLAMA_REPO_URL } else { "https://www.modelscope.cn/models/LLM-Research/Meta-Llama-3-8B-Instruct" }
$script:Llm2VecPeftRepoUrl = if ($env:KIMODO_LLM2VEC_PEFT_REPO_URL) { $env:KIMODO_LLM2VEC_PEFT_REPO_URL } else { "https://www.modelscope.cn/models/oneyoungmean/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised" }

function Write-Line {
  param([string]$Message)
  if ($script:OutputMode -ieq "file") {
    Add-Content -LiteralPath $script:LogPath -Value $Message -Encoding UTF8
    return
  }
  Write-Host $Message
}

function Parse-Args {
  param([string[]]$InputArgs)

  for ($i = 0; $i -lt $InputArgs.Count; $i++) {
    switch -Regex ($InputArgs[$i]) {
      "^--output$" { $i++; $script:OutputMode = $InputArgs[$i]; continue }
      "^--log$" { $i++; $script:LogPath = $InputArgs[$i]; continue }
      "^--unlock-stale$" { $script:UnlockStale = $true; continue }
      "^--force$" { $script:ForceSync = $true; continue }
      "^--model$" { $i++; $script:ModelName = $InputArgs[$i]; continue }
      "^--device$" { $i++; $script:RunDevice = $InputArgs[$i]; continue }
      "^--cpu-text-encoder$" { $i++; $script:CpuTextEncoder = $InputArgs[$i]; continue }
      "^--venv$" { $i++; $script:VenvPy = $InputArgs[$i]; continue }
      "^--highvram$" { $script:HighVram = $true; continue }
      default { continue }
    }
  }
}

function Set-LocalGitContext {
  $gitCmd = Join-Path $script:RootDir "program\exe\git\cmd"
  $gitLfs = Join-Path $script:RootDir "program\exe\git\mingw32\bin"
  $pathParts = @()
  if (Test-Path (Join-Path $gitCmd "git.exe")) { $pathParts += $gitCmd }
  if (Test-Path (Join-Path $gitLfs "git-lfs.exe")) { $pathParts += $gitLfs }
  if ($pathParts.Count -gt 0) {
    $env:PATH = ($pathParts -join ";") + ";" + $env:PATH
  }
}

function Resolve-ModelAlias {
  param([string]$InputModel)
  $resolved = $InputModel
  switch -Regex ($InputModel.ToLowerInvariant()) {
    "^soma$" { $resolved = "Kimodo-SOMA-RP-v1"; break }
    "^soma-rp$" { $resolved = "Kimodo-SOMA-RP-v1"; break }
    "^kimodo-soma-rp$" { $resolved = "Kimodo-SOMA-RP-v1"; break }
    "^g1$" { $resolved = "Kimodo-G1-RP-v1"; break }
    "^g1-rp$" { $resolved = "Kimodo-G1-RP-v1"; break }
    "^kimodo-g1-rp$" { $resolved = "Kimodo-G1-RP-v1"; break }
    "^soma-seed$" { $resolved = "Kimodo-SOMA-SEED-v1"; break }
    "^kimodo-soma-seed$" { $resolved = "Kimodo-SOMA-SEED-v1"; break }
    "^g1-seed$" { $resolved = "Kimodo-G1-SEED-v1"; break }
    "^kimodo-g1-seed$" { $resolved = "Kimodo-G1-SEED-v1"; break }
    "^smplx$" { $resolved = "Kimodo-SMPLX-RP-v1"; break }
    "^smplx-rp$" { $resolved = "Kimodo-SMPLX-RP-v1"; break }
    "^kimodo-smplx-rp$" { $resolved = "Kimodo-SMPLX-RP-v1"; break }
  }

  if (-not $resolved.StartsWith("Kimodo-", [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Line "[ERROR] Unsupported model alias: $InputModel"
    return $null
  }

  $repoName = $resolved
  if ($resolved -ieq "Kimodo-SOMA-RP-v1") {
    $repoName = "Kimodo-SOMA-RP-v1.1"
  }

  [pscustomobject]@{
    ModelName = $resolved
    ModelDirName = $resolved
    ModelRepoName = $repoName
  }
}

function Normalize-RepoUrl {
  param([string]$RawUrl)
  $normalized = $RawUrl
  if ($RawUrl -match "modelscope\.cn/models/") {
    $tmp = $RawUrl.Replace("https://www.modelscope.cn/models/", "")
    $tmp = $tmp.Replace("http://www.modelscope.cn/models/", "")
    $tmp = $tmp.Replace("/models/", "")
    $tmp = $tmp.Replace(".git", "")
    $normalized = "https://www.modelscope.cn/$tmp.git"
  } elseif ($RawUrl.StartsWith("https://www.modelscope.cn/", [System.StringComparison]::OrdinalIgnoreCase) -or
            $RawUrl.StartsWith("https://huggingface.co/", [System.StringComparison]::OrdinalIgnoreCase)) {
    if (-not $RawUrl.Contains(".git")) {
      $normalized = "$RawUrl.git"
    }
  }
  return $normalized
}

function Test-SafetensorValid {
  param([string]$Path)
  if (-not (Test-Path $Path -PathType Leaf)) { return $false }
  return ((Get-Item $Path).Length -gt 1024)
}

function Test-GgufPresence {
  param([string]$DirPath)
  if (-not (Test-Path $DirPath -PathType Container)) { return $false }
  $file = Get-ChildItem -LiteralPath $DirPath -Recurse -Filter *.gguf -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $file) { return $false }
  return ($file.Length -gt 1024)
}

function Rotate-Lock {
  param([string]$RepoDir)
  $lockFile = Join-Path $RepoDir ".git\index.lock"
  if (-not (Test-Path $lockFile -PathType Leaf)) { return $true }
  try {
    $bak = "$lockFile.stale.$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    Move-Item -LiteralPath $lockFile -Destination $bak -Force
    Write-Line "[WARN] Rotated stale lock: $bak"
    return $true
  } catch {
    Write-Line "[ERROR] Failed to rotate stale lock: $lockFile"
    return $false
  }
}

function Backup-Dir {
  param([string]$DirPath)
  if (-not (Test-Path $DirPath)) { return $true }
  try {
    $backup = "$DirPath.broken.$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    Move-Item -LiteralPath $DirPath -Destination $backup -Force
    Write-Line "[WARN] Backed up to: $backup"
    return $true
  } catch {
    Write-Line "[ERROR] Failed to backup: $DirPath"
    return $false
  }
}

function Prepare-Repo {
  param([string]$RepoDir)
  if ($script:UnlockStale) {
    if (-not (Rotate-Lock $RepoDir)) { return $false }
  }

  & git -C $RepoDir rev-parse --verify HEAD *> $null
  if ($LASTEXITCODE -eq 0) { return $true }

  if (Test-Path (Join-Path $RepoDir "model.safetensors") -PathType Leaf) {
    Write-Line "[WARN] Existing non-git model directory found, keep local files: $RepoDir"
    return $true
  }

  return (Backup-Dir $RepoDir)
}

function Repair-Safetensor {
  param(
    [string]$DestDir,
    [string]$ReqFile,
    [string]$LfsInclude
  )

  $target = Join-Path $DestDir $ReqFile
  if (-not $ReqFile.EndsWith(".safetensors", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
  if (-not (Test-Path $target -PathType Leaf)) { return $true }
  if (Test-SafetensorValid $target) { return $true }

  Write-Line "[WARN] Corrupted safetensor detected: $target"
  try {
    $broken = "$target.broken.$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    Move-Item -LiteralPath $target -Destination $broken -Force
    Write-Line "[WARN] Archived corrupted safetensor: $broken"
  } catch {
    Write-Line "[ERROR] Failed to archive corrupted safetensor: $target"
    return $false
  }

  & git -C $DestDir checkout HEAD -- $ReqFile
  if ($LASTEXITCODE -ne 0) { return $false }
  & git -C $DestDir lfs pull --include=$LfsInclude
  if ($LASTEXITCODE -ne 0) { return $false }
  if (-not (Test-Path $target -PathType Leaf)) {
    Write-Line "[ERROR] Missing $ReqFile after repair sync: $DestDir"
    return $false
  }
  if (-not (Test-SafetensorValid $target)) {
    Write-Line "[ERROR] safetensors validation still failed after one-time repair: $target"
    return $false
  }
  Write-Line "[OK] safetensors repaired: $target"
  return $true
}

function Ensure-Repo {
  param(
    [string]$RepoUrl,
    [string]$DestDir,
    [string]$ReqFile,
    [string]$LfsInclude
  )

  if (-not $LfsInclude) { $LfsInclude = $ReqFile }
  $repoUrl = Normalize-RepoUrl $RepoUrl

  if (-not $script:ForceSync) {
    if ($ReqFile -eq ".gguf") {
      if ((Test-Path $DestDir -PathType Container) -and (Test-GgufPresence $DestDir)) {
        Write-Line "[INFO] Skip existing gguf model: $DestDir"
        return $true
      }
      if (Test-Path $DestDir -PathType Container) {
        Write-Line "[WARN] Existing GGUF directory has no .gguf files, forcing sync: $DestDir"
      }
    } else {
      $reqPath = Join-Path $DestDir $ReqFile
      if (Test-Path $reqPath -PathType Leaf) {
        Write-Line "[INFO] Skip existing model: $DestDir"
        return (Repair-Safetensor $DestDir $ReqFile $LfsInclude)
      }
    }
  }

  if ((Test-Path $DestDir -PathType Container) -and -not (Test-Path (Join-Path $DestDir ".git") -PathType Container)) {
    if (-not (Backup-Dir $DestDir)) { return $false }
  }

  if (-not (Test-Path $DestDir -PathType Container)) {
    Write-Line "[STEP] Cloning $repoUrl"
    $env:GIT_LFS_SKIP_SMUDGE = "1"
    & git clone --depth 1 $repoUrl $DestDir
    $cloneRc = $LASTEXITCODE
    Remove-Item Env:\GIT_LFS_SKIP_SMUDGE -ErrorAction SilentlyContinue
    if ($cloneRc -ne 0) { return $false }
  } else {
    if (-not (Prepare-Repo $DestDir)) { return $false }
    Write-Line "[STEP] Updating existing repo: $DestDir"
    $env:GIT_LFS_SKIP_SMUDGE = "1"
    & git -C $DestDir pull
    $pullRc = $LASTEXITCODE
    Remove-Item Env:\GIT_LFS_SKIP_SMUDGE -ErrorAction SilentlyContinue
    if ($pullRc -ne 0) {
      if (-not (Backup-Dir $DestDir)) { return $false }
      Write-Line "[STEP] Re-cloning $repoUrl"
      $env:GIT_LFS_SKIP_SMUDGE = "1"
      & git clone --depth 1 $repoUrl $DestDir
      $recloneRc = $LASTEXITCODE
      Remove-Item Env:\GIT_LFS_SKIP_SMUDGE -ErrorAction SilentlyContinue
      if ($recloneRc -ne 0) { return $false }
    }
  }

  if (-not (Prepare-Repo $DestDir)) { return $false }
  & git -C $DestDir lfs pull --include=$LfsInclude
  if ($LASTEXITCODE -ne 0) { return $false }

  if ($ReqFile -eq ".gguf") {
    if (-not (Test-GgufPresence $DestDir)) {
      Write-Line "[ERROR] Missing .gguf files after sync: $DestDir"
      return $false
    }
  } else {
    $reqPath = Join-Path $DestDir $ReqFile
    if (-not (Test-Path $reqPath -PathType Leaf)) {
      & git -C $DestDir checkout HEAD -- $ReqFile
      if ($LASTEXITCODE -ne 0) { return $false }
      & git -C $DestDir lfs pull --include=$LfsInclude
      if ($LASTEXITCODE -ne 0) { return $false }
    }
    if (-not (Test-Path $reqPath -PathType Leaf)) {
      Write-Line "[ERROR] Missing $ReqFile after sync: $DestDir"
      return $false
    }
  }

  return (Repair-Safetensor $DestDir $ReqFile $LfsInclude)
}

function Get-SnapshotSource {
  param([string]$RepoUrl)
  $urlNoGit = $RepoUrl.Replace(".git", "")
  if ($urlNoGit.StartsWith("https://huggingface.co/", [System.StringComparison]::OrdinalIgnoreCase)) {
    return [pscustomobject]@{
      RepoId = $urlNoGit.Substring(24)
      Endpoint = ""
    }
  }
  Write-Line "[WARN] Snapshot fallback currently supports Hugging Face URLs only: $RepoUrl"
  return $null
}

function Ensure-RepoSnapshot {
  param(
    [string]$RepoUrl,
    [string]$DestDir,
    [string]$ReqFile,
    [string]$LfsInclude
  )

  if (-not $LfsInclude) { $LfsInclude = $ReqFile }
  $repoUrl = Normalize-RepoUrl $RepoUrl
  $source = Get-SnapshotSource $repoUrl
  if ($null -eq $source) { return $false }

  if (-not $script:VenvPy) {
    Write-Line "[ERROR] Snapshot fallback requires VENV_PY but it is not set."
    return $false
  }
  if (-not (Test-Path $script:VenvPy -PathType Leaf)) {
    Write-Line "[ERROR] Snapshot fallback requires venv python, not found: $($script:VenvPy)"
    return $false
  }

  if ((Test-Path $DestDir -PathType Container) -and -not (Test-Path (Join-Path $DestDir ".git") -PathType Container)) {
    if (-not (Backup-Dir $DestDir)) { return $false }
  }

  $allowPatterns = if ($ReqFile -eq ".gguf") { "*.gguf" } else { $LfsInclude }
  if (-not $allowPatterns) { $allowPatterns = "*" }

  Write-Line "[STEP] Snapshot fallback download $($source.RepoId) -> $DestDir"
  $snapshotLog = Join-Path $env:TEMP ("kimodo_snapshot_{0}.log" -f ([System.Guid]::NewGuid().ToString("N").Substring(0,8)))
  $py = "from huggingface_hub import snapshot_download; raw=r'$allowPatterns'; pats=None if (not raw or raw=='*') else [p.strip() for p in raw.split(',') if p.strip()]; snapshot_download(repo_id=r'$($source.RepoId)', local_dir=r'$DestDir', allow_patterns=pats, endpoint=(r'$($source.Endpoint)' if r'$($source.Endpoint)' else None), max_workers=4)"
  & $script:VenvPy -c $py *> $snapshotLog
  $snapshotRc = $LASTEXITCODE
  if (Test-Path $snapshotLog -PathType Leaf) {
    Get-Content -LiteralPath $snapshotLog | ForEach-Object { Write-Line "[DEBUG] snapshot fallback: $_" }
    Remove-Item -LiteralPath $snapshotLog -Force -ErrorAction SilentlyContinue
  }
  if ($snapshotRc -ne 0) {
    Write-Line "[WARN] Snapshot fallback failed: repo=$($source.RepoId) endpoint=$($source.Endpoint)"
    return $false
  }

  if ($ReqFile -eq ".gguf") {
    if (-not (Test-GgufPresence $DestDir)) {
      Write-Line "[ERROR] Missing .gguf files after snapshot fallback: $DestDir"
      return $false
    }
  } else {
    $reqPath = Join-Path $DestDir $ReqFile
    if (-not (Test-Path $reqPath -PathType Leaf)) {
      Write-Line "[ERROR] Missing $ReqFile after snapshot fallback: $DestDir"
      return $false
    }
  }

  return (Repair-Safetensor $DestDir $ReqFile $LfsInclude)
}

function Ensure-RepoWithFallback {
  param(
    [string]$PrimaryRepoUrl,
    [string]$FallbackRepoUrl,
    [string]$DestDir,
    [string]$ReqFile,
    [string]$LfsInclude
  )

  if (Ensure-Repo $PrimaryRepoUrl $DestDir $ReqFile $LfsInclude) { return $true }
  if ($FallbackRepoUrl) {
    Write-Line "[WARN] Primary repo failed, fallback to: $FallbackRepoUrl"
    if (Ensure-Repo $FallbackRepoUrl $DestDir $ReqFile $LfsInclude) {
      Write-Line "[OK] Fallback repo succeeded: $FallbackRepoUrl"
      return $true
    }
  }
  Write-Line "[WARN] Git-based sync failed, trying direct file download fallback: $DestDir"
  if (Ensure-RepoSnapshot $PrimaryRepoUrl $DestDir $ReqFile $LfsInclude) { return $true }
  if ($FallbackRepoUrl) {
    return (Ensure-RepoSnapshot $FallbackRepoUrl $DestDir $ReqFile $LfsInclude)
  }
  return $false
}

function Ensure-RepoAny {
  param(
    [string]$RepoUrl,
    [string]$DestDir,
    [string]$ReqA,
    [string]$ReqB,
    [string]$LfsInclude
  )
  if (Ensure-Repo $RepoUrl $DestDir $ReqA $LfsInclude) { return $true }
  if (Ensure-Repo $RepoUrl $DestDir $ReqB $LfsInclude) { return $true }
  Write-Line "[ERROR] Missing required files after sync: $DestDir"
  Write-Line "[ERROR] Need one of: $ReqA or $ReqB"
  return $false
}

function Get-TextEncoderAssetState {
  $ggufPresent = Test-GgufPresence (Join-Path $script:ModelsDir "Meta-Llama-3.1-8B-Instruct-hf-Q4_K_M-GGUF")
  $nf4Present = Test-SafetensorValid (Join-Path $script:ModelsDir "KIMODO-Meta3_llm2vec_NF4\model.safetensors")

  $fullBaseIndex = Join-Path $script:ModelsDir "Meta-Llama-3-8B-Instruct\model.safetensors.index.json"
  $fullBaseModel = Join-Path $script:ModelsDir "Meta-Llama-3-8B-Instruct\model.safetensors"
  $fullBasePresent = (Test-Path $fullBaseIndex -PathType Leaf) -or (Test-SafetensorValid $fullBaseModel)

  $fullPeftAdapter = Join-Path $script:ModelsDir "LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised\adapter_model.safetensors"
  $fullPeftModel = Join-Path $script:ModelsDir "LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised\model.safetensors"
  $fullPeftPresent = (Test-SafetensorValid $fullPeftAdapter) -or (Test-SafetensorValid $fullPeftModel)

  $state = [pscustomobject]@{
    Required = $true
    Reason = "missing_assets"
    GgufPresent = [int]$ggufPresent
    Nf4Present = [int]$nf4Present
    FullBasePresent = [int]$fullBasePresent
    FullPeftPresent = [int]$fullPeftPresent
  }

  if ($script:RunDevice -and $script:RunDevice.ToLowerInvariant() -eq "cpu" -and $script:CpuTextEncoder.ToLowerInvariant() -eq "gguf") {
    if ($ggufPresent) {
      $state.Required = $false
      $state.Reason = "cpu_gguf_present"
    } else {
      $state.Reason = "cpu_gguf_missing"
    }
    return $state
  }

  if ($script:HighVram) {
    if ($ggufPresent -and $fullBasePresent -and $fullPeftPresent) {
      $state.Required = $false
      $state.Reason = "highvram_all_present"
    } else {
      $state.Reason = "highvram_missing_assets"
    }
    return $state
  }

  if ($ggufPresent -and $nf4Present) {
    $state.Required = $false
    $state.Reason = "nf4_and_gguf_present"
  } else {
    $state.Reason = "nf4_or_gguf_missing"
  }
  return $state
}

function Get-VramDecision {
  Write-Line "[DEBUG] decide_download_gguf: run_device=$($script:RunDevice) cpu_text_encoder=$($script:CpuTextEncoder) venv=$($script:VenvPy)"

  if ($script:RunDevice -and $script:RunDevice.ToLowerInvariant() -eq "cpu" -and $script:CpuTextEncoder.ToLowerInvariant() -eq "gguf") {
    Write-Line "[INFO] Explicit CPU run (cpu text encoder=gguf) -> GGUF download enabled."
    return [pscustomobject]@{
      DownloadGguf = $true
      Reason = "forced_cpu"
      VramTotalGb = "none"
      ProbeStatus = "forced_cpu"
      ProbeBackend = "forced_cpu"
    }
  }

  $vramTotalGb = "none"
  $probeBackend = "none"
  $probeStatus = "unknown"

  $nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
  if ($null -ne $nvidiaSmi) {
    $probeStatus = "nvidia-smi"
    if ($script:VramProbeLogEnabled) { Write-Line "[DEBUG] VRAM probe backend: nvidia-smi ($($nvidiaSmi.Source))" }
    $rawRows = & $nvidiaSmi.Source --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
    $maxMb = $null
    foreach ($row in $rawRows) {
      $trimmed = ([string]$row).Trim()
      $mb = 0.0
      if ([double]::TryParse($trimmed, [ref]$mb)) {
        if ($null -eq $maxMb -or $mb -gt $maxMb) { $maxMb = $mb }
      }
    }
    if ($null -ne $maxMb) {
      $vramTotalGb = [math]::Round($maxMb / 1024.0, 2).ToString()
      $probeBackend = "nvidia-smi"
      if ($script:VramProbeLogEnabled) { Write-Line "[DEBUG] VRAM probe result: max_total=${vramTotalGb}GB from nvidia-smi" }
    } elseif ($script:VramProbeLogEnabled) {
      Write-Line "[WARN] VRAM probe via nvidia-smi returned no rows."
    }
  }

  if ($vramTotalGb -eq "none") {
    if ($script:VenvPy -and (Test-Path $script:VenvPy -PathType Leaf)) {
      $probeStatus = "torch"
      if ($script:VramProbeLogEnabled) { Write-Line "[DEBUG] VRAM probe fallback python: $($script:VenvPy)" }
      $probeLog = Join-Path $env:TEMP ("kimodo_vram_probe_{0}.log" -f ([System.Guid]::NewGuid().ToString("N").Substring(0,8)))
      $py = "import torch; print('probe_total=' + (str(round(torch.cuda.get_device_properties(0).total_memory/1073741824,2)) if (torch.cuda.is_available() and torch.cuda.device_count()>0) else 'none')); print('available=' + str(torch.cuda.is_available())); print('device_count=' + str(torch.cuda.device_count())); print('torch_cuda=' + str(torch.version.cuda))"
      & $script:VenvPy -c $py *> $probeLog
      $probeRc = $LASTEXITCODE
      if (Test-Path $probeLog -PathType Leaf) {
        foreach ($line in (Get-Content -LiteralPath $probeLog)) {
          if ($line -like "probe_total=*") { $vramTotalGb = $line.Substring(12) }
          elseif ($line -like "available=*") { $script:VramProbeAvailable = $line.Substring(10) }
          elseif ($line -like "device_count=*") { $script:VramProbeDeviceCount = $line.Substring(13) }
          elseif ($line -like "torch_cuda=*") { $script:VramProbeTorchCuda = $line.Substring(11) }
        }
        Remove-Item -LiteralPath $probeLog -Force -ErrorAction SilentlyContinue
      }
      if ($script:VramProbeLogEnabled) {
        Write-Line "[DEBUG] VRAM probe rc=$probeRc available=$($script:VramProbeAvailable) device_count=$($script:VramProbeDeviceCount) torch_cuda=$($script:VramProbeTorchCuda) total=$vramTotalGb"
      }
      if ($vramTotalGb -ne "none") { $probeBackend = "torch" }
    } else {
      $probeStatus = "missing_python"
      if ($script:VramProbeLogEnabled) { Write-Line "[WARN] VRAM probe skipped: venv python not found: $($script:VenvPy)" }
    }
  }

  if ($vramTotalGb -eq "none" -or [string]::IsNullOrWhiteSpace($vramTotalGb)) {
    Write-Line "[INFO] No usable GPU detected -> GGUF download enabled."
    return [pscustomobject]@{
      DownloadGguf = $true
      Reason = "no_gpu"
      VramTotalGb = "none"
      ProbeStatus = $probeStatus
      ProbeBackend = $probeBackend
    }
  }

  $asDouble = 0.0
  [void][double]::TryParse($vramTotalGb, [ref]$asDouble)
  if ($asDouble -lt 6.0) {
    Write-Line "[INFO] VRAM=${vramTotalGb}GB (<6GB, backend=$probeBackend) -> GGUF download enabled."
    return [pscustomobject]@{
      DownloadGguf = $true
      Reason = "vram_lt_6g"
      VramTotalGb = $vramTotalGb
      ProbeStatus = $probeStatus
      ProbeBackend = $probeBackend
    }
  }

  Write-Line "[INFO] VRAM=${vramTotalGb}GB (>=6GB, backend=$probeBackend) -> local encoder."
  return [pscustomobject]@{
    DownloadGguf = $false
    Reason = "vram_ge_6g"
    VramTotalGb = $vramTotalGb
    ProbeStatus = $probeStatus
    ProbeBackend = $probeBackend
  }
}

function Invoke-Main {
  New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
  New-Item -ItemType Directory -Force -Path $script:ModelsDir | Out-Null
  Set-LocalGitContext

  Write-Line "[DEBUG] context: root=$script:RootDir models=$script:ModelsDir output=$script:OutputMode log=$script:LogPath"
  Write-Line "[DEBUG] args: model=$script:ModelName device=$script:RunDevice cpu_text_encoder=$script:CpuTextEncoder highvram=$([int]$script:HighVram) force_sync=$([int]$script:ForceSync) unlock_stale=$([int]$script:UnlockStale)"
  Write-Line "[DEBUG] venv: $script:VenvPy"
  Write-Line "[DEBUG] env hints: KIMODO_CPU_TEXT_ENCODER=$($env:KIMODO_CPU_TEXT_ENCODER) KIMODO_FORCE_GGUF=$($env:KIMODO_FORCE_GGUF)"

  Write-Line "[STEP] Downloading models (single-thread)..."
  $alias = Resolve-ModelAlias $script:ModelName
  if ($null -eq $alias) { return 1 }

  $script:ModelName = $alias.ModelName
  $modelDirName = $alias.ModelDirName
  $modelRepoName = $alias.ModelRepoName
  $modelRepoUrl = "https://www.modelscope.cn/nv-community/$modelRepoName.git"
  $modelRepoFallback = ""
  switch ($modelRepoName) {
    "Kimodo-SOMA-RP-v1.1" { $modelRepoFallback = "https://huggingface.co/nvidia/Kimodo-SOMA-RP-v1.1" }
    "Kimodo-SMPLX-RP-v1" { $modelRepoFallback = "https://huggingface.co/nvidia/Kimodo-SMPLX-RP-v1" }
    "Kimodo-G1-RP-v1" { $modelRepoFallback = "https://huggingface.co/nvidia/Kimodo-G1-RP-v1" }
    "Kimodo-SOMA-SEED-v1" { $modelRepoFallback = "https://huggingface.co/nvidia/Kimodo-SOMA-SEED-v1" }
    "Kimodo-SOMA-SEED-v1.1" { $modelRepoFallback = "https://huggingface.co/nvidia/Kimodo-SOMA-SEED-v1.1" }
    "Kimodo-G1-SEED-v1" { $modelRepoFallback = "https://huggingface.co/nvidia/Kimodo-G1-SEED-v1" }
  }

  Write-Line "[DEBUG] alias resolved: name=$($script:ModelName) dir=$modelDirName repo=$modelRepoName"
  Write-Line "[DEBUG] model repo urls: primary=$modelRepoUrl fallback=$modelRepoFallback"
  if (-not (Ensure-RepoWithFallback $modelRepoUrl $modelRepoFallback (Join-Path $script:ModelsDir $modelDirName) "model.safetensors" "*")) {
    return 1
  }

  $assetState = Get-TextEncoderAssetState
  Write-Line "[DEBUG] text encoder state: required=$([int]$assetState.Required) reason=$($assetState.Reason) gguf=$($assetState.GgufPresent) nf4=$($assetState.Nf4Present) full_base=$($assetState.FullBasePresent) full_peft=$($assetState.FullPeftPresent)"
  if (-not $assetState.Required) {
    $script:GgufDecisionReason = "assets_present"
    $script:DownloadGguf = "skip"
    Write-Line "[INFO] Text encoder assets already present, skip VRAM probe and encoder download."
    Write-Line "[OK] download_model complete."
    return 0
  }

  $decision = Get-VramDecision
  $script:DownloadGguf = if ($decision.DownloadGguf) { "1" } else { "0" }
  $script:GgufDecisionReason = $decision.Reason
  $script:VramProbeStatus = $decision.ProbeStatus
  Write-Line "[DEBUG] GGUF decision: DOWNLOAD_GGUF=$script:DownloadGguf reason=$($decision.Reason) vram_total=$($decision.VramTotalGb) probe_status=$($decision.ProbeStatus)"

  if ($decision.DownloadGguf) {
    Write-Line "[STEP] GGUF mode enabled: downloading GGUF text encoder (skip local NF4/full encoder)"
    if (-not (Ensure-RepoWithFallback $script:GgufRepoUrl $script:GgufRepoUrlFallback (Join-Path $script:ModelsDir "Meta-Llama-3.1-8B-Instruct-hf-Q4_K_M-GGUF") ".gguf" "*")) {
      return 1
    }
  } elseif ($script:HighVram) {
    Write-Line "[STEP] highvram mode enabled: full text-encoder assets"
    if (-not (Ensure-Repo $script:MetaLlamaRepoUrl (Join-Path $script:ModelsDir "Meta-Llama-3-8B-Instruct") "model.safetensors.index.json" "*")) {
      return 1
    }
    if (-not (Ensure-RepoAny $script:Llm2VecPeftRepoUrl (Join-Path $script:ModelsDir "LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised") "adapter_model.safetensors" "model.safetensors" "*")) {
      return 1
    }
  } else {
    if (-not (Ensure-RepoWithFallback $script:Llm2VecNf4RepoUrl $script:Llm2VecNf4RepoUrlFallback (Join-Path $script:ModelsDir "KIMODO-Meta3_llm2vec_NF4") "model.safetensors" "*")) {
      return 1
    }
  }

  Write-Line "[OK] download_model complete."
  return 0
}

Parse-Args $CliArgs

if ($script:OutputMode -ieq "file") {
  $logParent = Split-Path -Parent $script:LogPath
  if ($logParent) {
    New-Item -ItemType Directory -Force -Path $logParent | Out-Null
  }
  Set-Content -LiteralPath $script:LogPath -Value $null -Encoding UTF8
  try {
    exit (Invoke-Main)
  } catch {
    Add-Content -LiteralPath $script:LogPath -Value ("[ERROR] " + $_.Exception.Message) -Encoding UTF8
    exit 1
  }
}

exit (Invoke-Main)
