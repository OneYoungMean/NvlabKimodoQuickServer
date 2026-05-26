param(
    [string]$GgufPath = "",
    [string]$ModelsRoot = ""
)

$ErrorActionPreference = "Stop"

$root = "C:\nvlab\NvlabKimodoQuickServer"
$setupBat = Join-Path $root "bash\setup.bat"
$runBat = Join-Path $root "run_server.bat"
$clientPs1 = Join-Path $root "example\example_run_server_tpose_client.ps1"
$llamaExe = Join-Path $root "program\exe\llama\llama-server.exe"
$logDir = Join-Path $root "log"
$setupLog = Join-Path $logDir "test_cpu_local_llama_setup.log"
$runLog = Join-Path $logDir "test_cpu_local_llama_run.log"
$clientLog = Join-Path $logDir "test_cpu_local_llama_client.log"
$portFile = Join-Path $root "serverport"
$recycleDir = Join-Path $root "archive\recycle"

if ([string]::IsNullOrWhiteSpace($ModelsRoot)) {
    $ModelsRoot = $env:KIMODO_TEST_MODELS_ROOT
}
if ([string]::IsNullOrWhiteSpace($ModelsRoot)) {
    $ModelsRoot = "C:\nvlab\models~"
}
if ([string]::IsNullOrWhiteSpace($GgufPath)) {
    $GgufPath = $env:KIMODO_GGUF_MODEL_PATH
}

Write-Host "[INFO] ROOT=$root"
Write-Host "[INFO] MODELS_ROOT=$ModelsRoot"
Write-Host "[INFO] GGUF_PATH=$GgufPath"

if (-not (Test-Path -LiteralPath $setupBat)) { throw "Missing setup.bat: $setupBat" }
if (-not (Test-Path -LiteralPath $runBat)) { throw "Missing run_server.bat: $runBat" }
if (-not (Test-Path -LiteralPath $clientPs1)) { throw "Missing client script: $clientPs1" }
if (-not (Test-Path -LiteralPath $llamaExe)) { throw "Missing local llama-server: $llamaExe" }
if (-not (Test-Path -LiteralPath $ModelsRoot)) { throw "Models root not found: $ModelsRoot" }
if ([string]::IsNullOrWhiteSpace($GgufPath)) { throw "GGUF path required." }
if (-not (Test-Path -LiteralPath $GgufPath)) { throw "GGUF path not found: $GgufPath" }
$ggufItem = Get-Item -LiteralPath $GgufPath
if ($ggufItem.PSIsContainer) {
    $firstGguf = Get-ChildItem -LiteralPath $GgufPath -Recurse -Filter *.gguf -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $firstGguf) { throw "No .gguf file found under: $GgufPath" }
    $GgufPath = $firstGguf.FullName
    $ggufItem = $firstGguf
}
if ($ggufItem.Length -lt 1048576) {
    throw "GGUF file too small (<1MB), likely invalid: $($ggufItem.FullName)"
}

New-Item -ItemType Directory -Path $logDir -Force | Out-Null
New-Item -ItemType Directory -Path $recycleDir -Force | Out-Null
foreach ($f in @($setupLog, $runLog, $clientLog, $portFile)) {
    if (Test-Path -LiteralPath $f) {
        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
        $dst = Join-Path $recycleDir ("{0}.{1}.{2}" -f (Split-Path -Leaf $f), $ts, (Get-Random))
        Move-Item -LiteralPath $f -Destination $dst -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[STEP] setup cpu"
& $setupBat --device cpu --output file --log $setupLog
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] setup failed"
    if (Test-Path -LiteralPath $setupLog) { Get-Content -LiteralPath $setupLog -Tail 120 }
    exit 1
}

Write-Host "[STEP] start run_server (cpu+gguf)"
$runCmd = "set KIMODO_CPU_TEXT_ENCODER=gguf && set KIMODO_GGUF_MODEL_PATH=$GgufPath && call `"$runBat`" --model Kimodo-SOMA-RP-v1 --device cpu --models-root `"$ModelsRoot`" --output file --log `"$runLog`""
$proc = Start-Process -FilePath "cmd.exe" -ArgumentList @("/d","/c",$runCmd) -WorkingDirectory $root -PassThru -WindowStyle Normal

try {
    Write-Host "[STEP] wait serverport"
    $hostName = $null
    $port = $null
    $deadline = (Get-Date).AddSeconds(180)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $portFile) {
            $raw = (Get-Content -LiteralPath $portFile -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($raw -and $raw.Contains(":")) {
                $parts = $raw.Split(":",2)
                if ($parts.Count -eq 2 -and $parts[0] -and $parts[1]) {
                    $hostName = $parts[0]
                    $port = [int]$parts[1]
                    break
                }
            }
        }
        Start-Sleep -Seconds 1
    }
    if (-not $hostName -or -not $port) {
        Write-Host "[ERROR] serverport timeout"
        if (Test-Path -LiteralPath $runLog) { Get-Content -LiteralPath $runLog -Tail 120 }
        throw "serverport timeout"
    }
    Write-Host "[INFO] endpoint=$hostName`:$port"

    $env:KIMODO_TEST_GENERATE_WAIT_MINUTES = "10"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $clientPs1 -HostName $hostName -Port $port -Prompt "tpose" -Duration 0.3 -Seed 1 -DiffusionSteps 1 -ConstraintsJson '""' *> $clientLog
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] client failed"
        if (Test-Path -LiteralPath $clientLog) { Get-Content -LiteralPath $clientLog -Tail 120 }
        if (Test-Path -LiteralPath $runLog) { Get-Content -LiteralPath $runLog -Tail 120 }
        throw "client failed"
    }
    $done = Select-String -Path $clientLog -Pattern '"status":"done"' -SimpleMatch -ErrorAction SilentlyContinue
    if (-not $done) {
        Write-Host "[ERROR] client log missing done"
        if (Test-Path -LiteralPath $clientLog) { Get-Content -LiteralPath $clientLog -Tail 120 }
        throw "missing done"
    }

    Write-Host "[OK] cpu local llama route test passed"
    exit 0
}
finally {
    if ($proc -and -not $proc.HasExited) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine -match 'kimodo\.bridge\.bridge_server' -and $_.CommandLine -match [regex]::Escape($root) } |
        ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
}
