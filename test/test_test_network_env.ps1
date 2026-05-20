param(
  [int]$TimeoutSec = 20
)

$ErrorActionPreference = "Stop"
$tag = "[test_network_env.ps1]"

function Test-UrlHead {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [int]$Timeout = 20
  )
  try {
    Invoke-WebRequest -UseBasicParsing -Method Head -TimeoutSec $Timeout -Uri $Url | Out-Null
    return $true
  } catch {
    return $false
  }
}

$pipPrimary = @(
  "https://pypi.doubanio.com/simple",
  "https://mirrors.aliyun.com/pypi/simple/",
  "https://pypi.org/simple"
)

$pipExtra = @(
  "https://pypi.oystermercury.top/ms",
  "https://gitlab.inria.fr/api/v4/projects/18692/packages/pypi/simple"
)

$pythonSources = @(
  "https://mirrors.tuna.tsinghua.edu.cn/python/",
  "https://www.python.org/ftp/python/"
)

Write-Output "[STEP]$tag Checking PIP primary indexes..."
$selectedPrimary = $null
foreach ($u in $pipPrimary) {
  $ok = Test-UrlHead -Url $u -Timeout $TimeoutSec
  Write-Output ("[CHECK]{0} {1}" -f ($(if ($ok) { "[OK] " } else { "[FAIL]" }), $u))
  if (-not $selectedPrimary -and $ok) { $selectedPrimary = $u }
}
if (-not $selectedPrimary) {
  Write-Output "[ERROR]$tag No reachable PIP primary index."
} else {
  Write-Output "[INFO]$tag Selected PIP_INDEX_URL=$selectedPrimary"
}

Write-Output "[STEP]$tag Checking PIP extra indexes..."
$reachableExtra = @()
foreach ($u in $pipExtra) {
  $ok = Test-UrlHead -Url $u -Timeout $TimeoutSec
  Write-Output ("[CHECK]{0} {1}" -f ($(if ($ok) { "[OK] " } else { "[FAIL]" }), $u))
  if ($ok) { $reachableExtra += $u }
}
if ($reachableExtra.Count -gt 0) {
  Write-Output "[INFO]$tag Reachable PIP_EXTRA_INDEX_URL entries:"
  $reachableExtra | ForEach-Object { Write-Output ("  - " + $_) }
} else {
  Write-Output "[WARN]$tag No PIP extra index is reachable."
}

Write-Output "[STEP]$tag Checking Python download sources..."
$pythonOk = $false
foreach ($u in $pythonSources) {
  $ok = Test-UrlHead -Url $u -Timeout $TimeoutSec
  Write-Output ("[CHECK]{0} {1}" -f ($(if ($ok) { "[OK] " } else { "[FAIL]" }), $u))
  if ($ok) { $pythonOk = $true }
}
if (-not $pythonOk) {
  Write-Output "[ERROR]$tag No reachable Python download source."
}

if (-not $selectedPrimary -or -not $pythonOk) {
  Write-Output "[RESULT]$tag FAILED"
  exit 1
}

Write-Output "[RESULT]$tag PASSED"
exit 0
