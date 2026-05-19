@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ------------------------------------------------------------
rem Test Unity bridge by TCP request flow:
rem 1) start launcher in background
rem 2) read serverport
rem 3) send ping/generate/quit via TCP
rem ------------------------------------------------------------

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%"

set "LAUNCHER=%ROOT_DIR%\start_kimodo_bridge_offline.bat"
set "MODEL=Kimodo-SOMA-RP-v1"
set "PORT_FILE=%ROOT_DIR%\serverport"
set "LOG_FILE=%ROOT_DIR%\bridge_test_generate_tpose.log"
set "CLIENT_LOG_FILE=%ROOT_DIR%\bridge_test_generate_tpose_client.log"
set "CLIENT_PS1=%ROOT_DIR%\test_unity_bridge_generate_tpose_client.ps1"
set "OUTPUT_MODE=%KIMODO_TPOSE_OUTPUT%"
if not defined OUTPUT_MODE set "OUTPUT_MODE=console"

if not exist "%LAUNCHER%" (
  echo [ERROR] Launcher not found: %LAUNCHER%
  exit /b 1
)
if not exist "%CLIENT_PS1%" (
  echo [ERROR] Client script not found: %CLIENT_PS1%
  exit /b 1
)

echo [TEST] ROOT_DIR=%ROOT_DIR%
echo [TEST] MODEL=%MODEL%
echo [TEST] MODE=%OUTPUT_MODE%
echo [TEST] Request: prompt=tpose, duration=5.0, seed=42

if exist "%PORT_FILE%" del /q "%PORT_FILE%" >nul 2>nul
if exist "%CLIENT_LOG_FILE%" del /q "%CLIENT_LOG_FILE%" >nul 2>nul

if /I "%OUTPUT_MODE%"=="file" (
  start "kimodo_bridge_test_launcher" /b cmd /d /c ""%LAUNCHER%" --kimodo-root "%ROOT_DIR%" --model "%MODEL%" > "%LOG_FILE%" 2>&1"
) else (
  start "kimodo_bridge_test_launcher" /b cmd /d /c ""%LAUNCHER%" --kimodo-root "%ROOT_DIR%" --model "%MODEL%""
)

set "HOST="
set "PORT="
set /a WAIT_SEC=0
:wait_port
if exist "%PORT_FILE%" (
  for /f "usebackq tokens=1,2 delims=:" %%A in ("%PORT_FILE%") do (
    set "HOST=%%A"
    set "PORT=%%B"
  )
)
if defined HOST if defined PORT goto got_port

ping 127.0.0.1 -n 2 >nul
set /a WAIT_SEC+=1
if %WAIT_SEC% geq 180 (
  echo [ERROR] Timeout waiting for serverport file: %PORT_FILE%
  exit /b 1
)
goto wait_port

:got_port
echo [TEST] Connected target from serverport: !HOST!:!PORT!

if /I "%OUTPUT_MODE%"=="file" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%CLIENT_PS1%" -HostName "%HOST%" -Port %PORT% -Prompt "tpose" -Duration 5.0 -Seed 42 -DiffusionSteps 100 -ConstraintsJson "" > "%CLIENT_LOG_FILE%" 2>&1
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%CLIENT_PS1%" -HostName "%HOST%" -Port %PORT% -Prompt "tpose" -Duration 5.0 -Seed 42 -DiffusionSteps 100 -ConstraintsJson ""
)
set "EXIT_CODE=%ERRORLEVEL%"

echo [TEST] Client exit code: %EXIT_CODE%

if /I "%OUTPUT_MODE%"=="file" call :summarize_log
exit /b %EXIT_CODE%

:summarize_log
echo [TEST] Inspect log: %LOG_FILE%
echo [TEST] Inspect client log: %CLIENT_LOG_FILE%
echo [TEST] Log tail (last 60 lines):
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%LOG_FILE%'; if(Test-Path -LiteralPath $p){ Get-Content -LiteralPath $p -Tail 60 }"
echo [TEST] Client log tail (last 60 lines):
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%CLIENT_LOG_FILE%'; if(Test-Path -LiteralPath $p){ Get-Content -LiteralPath $p -Tail 60 }"

findstr /c:"\"status\": \"ready\"" "%LOG_FILE%" >nul
if errorlevel 1 (
  echo [WARN] Did not find ready status in log.
) else (
  echo [OK] Found ready status in log.
)

findstr /c:"\"status\": \"done\"" "%CLIENT_LOG_FILE%" >nul
if errorlevel 1 (
  echo [WARN] Did not find done status in log.
) else (
  echo [OK] Found done status in log.
)

findstr /c:"\"status\": \"bye\"" "%CLIENT_LOG_FILE%" >nul
if errorlevel 1 (
  echo [WARN] Did not find bye status in log.
) else (
  echo [OK] Found bye status in log.
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$log='%CLIENT_LOG_FILE%';" ^
  "$done=Get-Content -LiteralPath $log | Where-Object { $_ -match '\"status\": \"done\"' } | Select-Object -Last 1;" ^
  "if(-not $done){ Write-Host '[TEST] No done payload found.'; exit 0 };" ^
  "$obj=$done | ConvertFrom-Json;" ^
  "$motion=$obj.motion_json_compact | ConvertFrom-Json;" ^
  "Write-Host ('[TEST] Motion frames={0}, joints={1}, fps={2}' -f $motion.num_frames,$motion.num_joints,$motion.fps)"

exit /b 0
