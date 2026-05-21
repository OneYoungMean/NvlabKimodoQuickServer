@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%\.."
set "SETUP_BAT=%ROOT_DIR%\bash\setup.bat"
set "LOG_DIR=%ROOT_DIR%\log"
set "SETUP_LOG=%LOG_DIR%\example_test_local_tools_setup.log"
set "SETUP_LOCK=%ROOT_DIR%\.setup.lock"

if not exist "%SETUP_BAT%" (
  echo [ERROR] setup.bat not found: %SETUP_BAT%
  exit /b 1
)
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul

echo [TEST] Root=%ROOT_DIR%
echo [TEST] Setup=%SETUP_BAT%
echo [TEST] Log=%SETUP_LOG%
echo [TEST] Force local uv+git toolchain check...

set "KIMODO_NETWORK_PROBE_TIMEOUT_SEC=1"
set "KIMODO_NETWORK_FALLBACK_HEAD_TIMEOUT_SEC=3"

call :wait_setup_lock
if errorlevel 1 exit /b 1

call "%SETUP_BAT%" --force --output file --log "%SETUP_LOG%"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo [ERROR] setup failed rc=%RC%
  if exist "%SETUP_LOG%" (
    echo [TEST] setup log tail:
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%SETUP_LOG%'; if(Test-Path -LiteralPath $p){Get-Content -LiteralPath $p -Tail 120}"
  )
  exit /b %RC%
)

findstr /C:"[INFO] Using local uv:" "%SETUP_LOG%" >nul
if errorlevel 1 (
  echo [ERROR] local uv marker not found in setup log.
  exit /b 2
)

findstr /C:"[OK] local git/git-lfs are ready in local context." "%SETUP_LOG%" >nul
if errorlevel 1 (
  echo [ERROR] local git/git-lfs marker not found in setup log.
  exit /b 3
)

echo [OK] Local uv and local git/git-lfs checks passed.
exit /b 0

:wait_setup_lock
if not exist "%SETUP_LOCK%" exit /b 0
echo [TEST] setup lock detected, waiting: %SETUP_LOCK%
set /a WAITED=0
:wait_loop
if not exist "%SETUP_LOCK%" (
  echo [TEST] setup lock cleared after %WAITED%s
  exit /b 0
)
ping 127.0.0.1 -n 2 >nul
set /a WAITED+=1
if %WAITED% GEQ 900 (
  echo [ERROR] Timeout waiting setup lock release: %SETUP_LOCK%
  exit /b 1
)
goto wait_loop
