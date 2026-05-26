@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%\.."
set "LOG_DIR=%ROOT_DIR%\log"
set "PORT_FILE=%ROOT_DIR%\serverport"
set "SETUP_LOG=%LOG_DIR%\test_cpu_local_llama_setup.log"
set "RUN_LOG=%LOG_DIR%\test_cpu_local_llama_run.log"
set "CLIENT_LOG=%LOG_DIR%\test_cpu_local_llama_client.log"
set "CLIENT_PS1=%ROOT_DIR%\example\example_run_server_tpose_client.ps1"

set "MODELS_ROOT=%KIMODO_TEST_MODELS_ROOT%"
if not defined MODELS_ROOT set "MODELS_ROOT=C:\nvlab\models~"
set "GGUF_PATH=%KIMODO_GGUF_MODEL_PATH%"
if not defined GGUF_PATH set "GGUF_PATH=%~1"

echo [INFO] ROOT_DIR=%ROOT_DIR%
echo [INFO] MODELS_ROOT=%MODELS_ROOT%
echo [INFO] GGUF_PATH=%GGUF_PATH%

if not exist "%ROOT_DIR%\bash\setup.bat" (
  echo [ERROR] missing setup: %ROOT_DIR%\bash\setup.bat
  exit /b 1
)
if not exist "%ROOT_DIR%\run_server.bat" (
  echo [ERROR] missing run_server: %ROOT_DIR%\run_server.bat
  exit /b 1
)
if not exist "%CLIENT_PS1%" (
  echo [ERROR] missing client ps1: %CLIENT_PS1%
  exit /b 1
)
if not exist "%ROOT_DIR%\program\exe\llama\llama-server.exe" (
  echo [ERROR] missing local llama-server.exe
  exit /b 1
)
if not exist "%MODELS_ROOT%" (
  echo [ERROR] models root not found: %MODELS_ROOT%
  exit /b 1
)
if not defined GGUF_PATH (
  echo [ERROR] GGUF path required. pass arg1 or set KIMODO_GGUF_MODEL_PATH.
  exit /b 1
)
if not exist "%GGUF_PATH%" (
  echo [ERROR] GGUF path not found: %GGUF_PATH%
  exit /b 1
)

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul
if exist "%SETUP_LOG%" del /f /q "%SETUP_LOG%" >nul 2>nul
if exist "%RUN_LOG%" del /f /q "%RUN_LOG%" >nul 2>nul
if exist "%CLIENT_LOG%" del /f /q "%CLIENT_LOG%" >nul 2>nul

echo [STEP] setup cpu
call "%ROOT_DIR%\bash\setup.bat" --device cpu --output file --log "%SETUP_LOG%"
if errorlevel 1 (
  echo [ERROR] setup failed
  powershell -NoProfile -ExecutionPolicy Bypass -Command "if(Test-Path '%SETUP_LOG%'){ Get-Content '%SETUP_LOG%' -Tail 120 }"
  exit /b 1
)

if exist "%PORT_FILE%" del /f /q "%PORT_FILE%" >nul 2>nul

echo [STEP] start run_server (cpu+gguf)
start "KIMODO_CPU_LOCAL_LLAMA_TEST" cmd /c "cd /d %ROOT_DIR% && set KIMODO_CPU_TEXT_ENCODER=gguf && set KIMODO_GGUF_MODEL_PATH=%GGUF_PATH% && call run_server.bat --model Kimodo-SOMA-RP-v1 --device cpu --models-root %MODELS_ROOT% --output file --log %RUN_LOG%"

echo [STEP] wait serverport
set "HOST="
set "PORT="
set /a I=0
:wait_port
if exist "%PORT_FILE%" (
  for /f "usebackq tokens=1,2 delims=:" %%A in ("%PORT_FILE%") do (
    set "HOST=%%A"
    set "PORT=%%B"
  )
)
if defined HOST if defined PORT goto port_ok
timeout /t 1 /nobreak >nul
set /a I=I+1
if %I% GEQ 180 (
  echo [ERROR] serverport timeout
  powershell -NoProfile -ExecutionPolicy Bypass -Command "if(Test-Path '%RUN_LOG%'){ Get-Content '%RUN_LOG%' -Tail 120 }"
  goto fail_kill
)
goto wait_port

:port_ok
echo [INFO] endpoint=%HOST%:%PORT%

set "KIMODO_TEST_GENERATE_WAIT_MINUTES=10"
powershell -NoProfile -ExecutionPolicy Bypass -File "%CLIENT_PS1%" -HostName "%HOST%" -Port %PORT% -Prompt "tpose" -Duration 0.3 -Seed 1 -DiffusionSteps 1 -ConstraintsJson "" > "%CLIENT_LOG%" 2>&1
if errorlevel 1 (
  echo [ERROR] client failed
  powershell -NoProfile -ExecutionPolicy Bypass -Command "if(Test-Path '%CLIENT_LOG%'){ Get-Content '%CLIENT_LOG%' -Tail 120 }"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "if(Test-Path '%RUN_LOG%'){ Get-Content '%RUN_LOG%' -Tail 120 }"
  goto fail_kill
)

findstr /I /C:"""status"":""done""" "%CLIENT_LOG%" >nul
if errorlevel 1 (
  echo [ERROR] client log missing done
  powershell -NoProfile -ExecutionPolicy Bypass -Command "if(Test-Path '%CLIENT_LOG%'){ Get-Content '%CLIENT_LOG%' -Tail 120 }"
  goto fail_kill
)

echo [OK] cpu local llama route test passed
exit /b 0

:fail_kill
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; $root=(Resolve-Path '%ROOT_DIR%').Path; $pat=[regex]::Escape($root); Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { $_.CommandLine -and $_.CommandLine -match 'kimodo\\.bridge\\.bridge_server' -and $_.CommandLine -match $pat } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
exit /b 1
