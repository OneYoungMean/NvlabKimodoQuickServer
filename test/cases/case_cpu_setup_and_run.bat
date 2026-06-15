@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%\..") do set "TEST_DIR=%%~fI"
for %%I in ("%TEST_DIR%\..") do set "ROOT_DIR=%%~fI"
set "LOG_DIR=%ROOT_DIR%\log"
set "RECYCLE_DIR=%ROOT_DIR%\archive\recycle"
set "MODELS_ROOT=C:\nvlab\models~"
set "EXAMPLE_BAT=%ROOT_DIR%\example\example_run_server_tpose.bat"

if not exist "%ROOT_DIR%\bash\setup.bat" (
  echo [ERROR] setup.bat missing.
  exit /b 1
)
if not exist "%ROOT_DIR%\run_server.bat" (
  echo [ERROR] run_server.bat missing.
  exit /b 1
)
if not exist "%EXAMPLE_BAT%" (
  echo [ERROR] example_run_server_tpose.bat missing: %EXAMPLE_BAT%
  exit /b 1
)
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul
if not exist "%RECYCLE_DIR%" mkdir "%RECYCLE_DIR%" >nul 2>nul

set "SETUP_LOG=%LOG_DIR%\test_cpu_setup.log"
call :archive_file "%SETUP_LOG%"

echo [STEP] setup cpu mode...
set "KIMODO_TEST_SETUP_DEVICE=cpu"
call "%ROOT_DIR%\bash\setup.bat" --output file --log "%SETUP_LOG%"
if errorlevel 1 (
  echo [ERROR] setup cpu failed.
  if exist "%SETUP_LOG%" powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%SETUP_LOG%' -Tail 120"
  exit /b 1
)

echo [STEP] run example tpose ^(cpu mode^)...
set "KIMODO_TEST_DEVICE=cpu"
set "KIMODO_TEST_MODEL=Kimodo-SOMA-RP-v1"
set "KIMODO_TEST_MODELS_ROOT=%MODELS_ROOT%"
pushd "%ROOT_DIR%" >nul
call "%EXAMPLE_BAT%"
set "EXAMPLE_RC=%ERRORLEVEL%"
popd >nul
if not "%EXAMPLE_RC%"=="0" (
  echo [ERROR] example tpose cpu failed rc=%EXAMPLE_RC%.
  exit /b %EXAMPLE_RC%
)

echo [OK] case_cpu_setup_and_run passed.
exit /b 0

:archive_file
set "ARCHIVE_TARGET=%~1"
if not exist "%ARCHIVE_TARGET%" exit /b 0
if not exist "%RECYCLE_DIR%" mkdir "%RECYCLE_DIR%" >nul 2>nul
set "TS=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "TS=%TS: =0%"
set "BASE=%~nx1"
set "DEST=%RECYCLE_DIR%\%BASE%.%TS%.%RANDOM%"
move "%ARCHIVE_TARGET%" "%DEST%" >nul 2>nul
exit /b 0
