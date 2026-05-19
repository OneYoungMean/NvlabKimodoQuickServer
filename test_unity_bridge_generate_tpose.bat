@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ------------------------------------------------------------
rem Simulate Unity bridge launch + one real generation request.
rem Request:
rem   prompt=tpose, duration=5.0s, seed=42, diffusion_steps=100
rem ------------------------------------------------------------

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%"
for %%I in ("%SCRIPT_DIR%\..") do set "WORKSPACE_ROOT=%%~fI"

set "LAUNCHER=%ROOT_DIR%\start_kimodo_bridge_offline.bat"
set "MODEL=Kimodo-SOMA-RP-v1"
set "REQ_FILE=%ROOT_DIR%\_bridge_test_generate_req.jsonl"
set "LOG_FILE=%ROOT_DIR%\bridge_test_generate_tpose.log"

if not exist "%LAUNCHER%" (
  echo [ERROR] Launcher not found: %LAUNCHER%
  exit /b 1
)

> "%REQ_FILE%" (
  echo {"cmd":"ping"}
  echo {"cmd":"generate","prompt":"tpose","duration":5.0,"seed":42,"diffusion_steps":100,"constraints_json":""}
  echo {"cmd":"quit"}
)

echo [TEST] ROOT_DIR=%ROOT_DIR%
echo [TEST] MODEL=%MODEL%
echo [TEST] LOG=%LOG_FILE%
echo [TEST] Request: prompt=tpose, duration=5.0, seed=42
echo [TEST] Request jsonl file: %REQ_FILE%
echo [TEST] Request payload begin ----
type "%REQ_FILE%"
echo [TEST] Request payload end   ----

type "%REQ_FILE%" | call "%LAUNCHER%" --kimodo-root "%ROOT_DIR%" --model "%MODEL%" > "%LOG_FILE%" 2>&1
set "EXIT_CODE=%ERRORLEVEL%"
del /q "%REQ_FILE%" >nul 2>nul

echo [TEST] Launcher exit code: %EXIT_CODE%
echo [TEST] Inspect log: %LOG_FILE%
echo [TEST] Log tail (last 40 lines):
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%LOG_FILE%'; if(Test-Path -LiteralPath $p){ Get-Content -LiteralPath $p -Tail 40 }"

findstr /c:"\"status\": \"ready\"" "%LOG_FILE%" >nul
if errorlevel 1 (
  echo [WARN] Did not find ready status in log.
) else (
  echo [OK] Found ready status in log.
)

findstr /c:"\"status\": \"done\"" "%LOG_FILE%" >nul
if errorlevel 1 (
  echo [WARN] Did not find done status in log.
) else (
  echo [OK] Found done status in log.
)

findstr /c:"\"status\": \"bye\"" "%LOG_FILE%" >nul
if errorlevel 1 (
  echo [WARN] Did not find bye status in log.
) else (
  echo [OK] Found bye status in log.
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$log='%LOG_FILE%';" ^
  "$done=Get-Content -LiteralPath $log | Where-Object { $_ -match '\"status\": \"done\"' } | Select-Object -Last 1;" ^
  "if(-not $done){ Write-Host '[TEST] No done payload found.'; exit 0 };" ^
  "$obj=$done | ConvertFrom-Json;" ^
  "$motion=$obj.motion_json_compact | ConvertFrom-Json;" ^
  "Write-Host ('[TEST] Motion frames={0}, joints={1}, fps={2}' -f $motion.num_frames,$motion.num_joints,$motion.fps)"

exit /b %EXIT_CODE%
