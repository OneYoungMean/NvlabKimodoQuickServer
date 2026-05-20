param(
  [int]$TimeoutSec = 8,
  [string]$EmitCmdFile = "",
  [switch]$Quiet
)

$ErrorActionPreference = "Stop"

function Write-Log {
  param([string]$Message)
  if (-not $Quiet) { Write-Output $Message }
}

function Test-HeadMs {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [int]$Timeout = 8
  )
  try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-WebRequest -UseBasicParsing -Method Head -TimeoutSec $Timeout -Uri $Url | Out-Null
    $sw.Stop()
    return [pscustomobject]@{ Ok = $true; Ms = [int]$sw.ElapsedMilliseconds; Url = $Url }
  } catch {
    return [pscustomobject]@{ Ok = $false; Ms = 2147483647; Url = $Url }
  }
}

function Pick-Best {
  param([object[]]$Candidates)
  $probed = @()
  foreach ($c in $Candidates) {
    $r = Test-HeadMs -Url $c.Url -Timeout $TimeoutSec
    $probed += [pscustomobject]@{
      Name = $c.Name
      Url = $c.Url
      Host = $c.Host
      Ok = $r.Ok
      Ms = $r.Ms
    }
    if ($r.Ok) {
      Write-Log ("[CHECK][OK] {0} {1} ({2} ms)" -f $c.Name, $c.Url, $r.Ms)
    } else {
      Write-Log ("[CHECK][FAIL] {0} {1}" -f $c.Name, $c.Url)
    }
  }

  $best = $probed | Where-Object { $_.Ok } | Sort-Object Ms, Name | Select-Object -First 1
  return [pscustomobject]@{
    Best = $best
    All = $probed
  }
}

$pipCandidates = @(
  [pscustomobject]@{ Name = "pypi"; Url = "https://pypi.org/simple"; Host = "pypi.org" },
  [pscustomobject]@{ Name = "tuna"; Url = "https://pypi.tuna.tsinghua.edu.cn/simple"; Host = "pypi.tuna.tsinghua.edu.cn" },
  [pscustomobject]@{ Name = "aliyun"; Url = "https://mirrors.aliyun.com/pypi/simple/"; Host = "mirrors.aliyun.com" }
)

$pythonZipCandidates = @(
  [pscustomobject]@{ Name = "python.org"; Url = "https://www.python.org/ftp/python/"; Host = "www.python.org"; Base = "https://www.python.org/ftp/python/" },
  [pscustomobject]@{ Name = "tuna-python"; Url = "https://mirrors.tuna.tsinghua.edu.cn/python/"; Host = "mirrors.tuna.tsinghua.edu.cn"; Base = "https://mirrors.tuna.tsinghua.edu.cn/python/" }
)

Write-Log "[STEP] Probing pip indexes..."
$pipPick = Pick-Best -Candidates $pipCandidates
if (-not $pipPick.Best) {
  Write-Output "[ERROR] No reachable pip index."
  exit 1
}

Write-Log "[STEP] Probing python zip mirrors..."
$pyPick = Pick-Best -Candidates $pythonZipCandidates
if (-not $pyPick.Best) {
  Write-Output "[ERROR] No reachable python zip source."
  exit 1
}

$pipIndex = $pipPick.Best.Url
$pipHost = $pipPick.Best.Host
$pythonBase = ($pythonZipCandidates | Where-Object { $_.Name -eq $pyPick.Best.Name } | Select-Object -First 1).Base

$pipArgs = "--index-url `"$pipIndex`" --trusted-host `"$pipHost`""

Write-Output "[RESULT] PIP_INDEX_URL=$pipIndex"
Write-Output "[RESULT] PIP_TRUSTED_HOST=$pipHost"
Write-Output "[RESULT] PIP_ARGS=$pipArgs"
Write-Output "[RESULT] PYTHON_ZIP_BASE=$pythonBase"

if (-not [string]::IsNullOrWhiteSpace($EmitCmdFile)) {
  $dir = Split-Path -Parent $EmitCmdFile
  if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }

  @(
    "@echo off"
    "set ""KIMODO_PIP_INDEX_URL=$pipIndex"""
    "set ""KIMODO_PIP_TRUSTED_HOST=$pipHost"""
    "set ""KIMODO_PIP_ARGS=--index-url $pipIndex --trusted-host $pipHost"""
    "set ""KIMODO_PY_ZIP_BASE=$pythonBase"""
  ) | Set-Content -LiteralPath $EmitCmdFile -Encoding ASCII
}

exit 0
