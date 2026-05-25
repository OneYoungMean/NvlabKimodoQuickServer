@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "SOURCE_DIR=%SCRIPT_DIR%\.."
for %%I in ("%SOURCE_DIR%") do set "SOURCE_DIR=%%~fI"
set "TARGET_ROOT=%SOURCE_DIR%\recycle\test"
set "TEST_BAT_REL=example\example_run_server_tpose.bat"
set "SHARED_MODELS_SRC=C:\nvlab\models"
set "SHARED_MODELS_ALT=C:\nvlab\models~"
set "TEST_MODELS_ROOT="
set "COPY_ONLY=%KIMODO_COPY_ONLY%"
if not defined COPY_ONLY set "COPY_ONLY=0"
set "COPY_DEST_FILE=%KIMODO_COPY_DEST_FILE%"

if not exist "%SOURCE_DIR%" (
  echo [ERROR] Source directory not found: %SOURCE_DIR%
  exit /b 1
)
if not exist "%TARGET_ROOT%" (
  mkdir "%TARGET_ROOT%" >nul 2>nul
  if errorlevel 1 (
    echo [ERROR] Failed to create target root: %TARGET_ROOT%
    exit /b 1
  )
)

for /f %%I in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-Date).ToString('yyyyMMdd_HHmmss_fff')"') do set "TS=%%I"
set "DEST_DIR=%TARGET_ROOT%\NvlabKimodoQuickServer_%TS%_%RANDOM%%RANDOM%"
set "DEST_TEST_BAT=%DEST_DIR%\%TEST_BAT_REL%"

mkdir "%DEST_DIR%" >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Failed to create destination: %DEST_DIR%
  exit /b 1
)

echo [INFO] SOURCE=%SOURCE_DIR%
echo [INFO] DEST=%DEST_DIR%
echo [STEP] Exporting committed files from git HEAD...
git -C "%SOURCE_DIR%" rev-parse --is-inside-work-tree >nul 2>nul
if errorlevel 1 (
  echo [ERROR] SOURCE is not a git work tree: %SOURCE_DIR%
  exit /b 1
)

where tar >nul 2>nul
if errorlevel 1 (
  echo [ERROR] tar not found in PATH. git archive export requires tar.
  exit /b 1
)

git -C "%SOURCE_DIR%" archive --format=tar HEAD | tar -xf - -C "%DEST_DIR%"
if errorlevel 1 (
  echo [ERROR] git archive export failed.
  exit /b 1
)

echo [OK] Copy complete: %DEST_DIR%
if not exist "%SHARED_MODELS_SRC%" (
  if exist "%SHARED_MODELS_ALT%" (
    set "SHARED_MODELS_SRC=%SHARED_MODELS_ALT%"
  )
)
if not exist "%SHARED_MODELS_SRC%" (
  echo [ERROR] Shared models source not found: C:\nvlab\models or C:\nvlab\models~
  exit /b 1
)
set "TEST_MODELS_ROOT=%SHARED_MODELS_SRC%"
echo [INFO] Test models root: %TEST_MODELS_ROOT%

if /I "%COPY_ONLY%"=="1" (
  echo [RESULT] DEST_DIR=%DEST_DIR%
  echo [RESULT] TEST_MODELS_ROOT=%TEST_MODELS_ROOT%
  if defined COPY_DEST_FILE (
    > "%COPY_DEST_FILE%" (
      echo DEST_DIR=%DEST_DIR%
      echo TEST_MODELS_ROOT=%TEST_MODELS_ROOT%
    )
    echo [INFO] Dest info file: %COPY_DEST_FILE%
  )
  exit /b 0
)

if not exist "%DEST_TEST_BAT%" (
  echo [ERROR] Test entry not found after copy: %DEST_TEST_BAT%
  exit /b 1
)

echo [STEP] Running test: %DEST_TEST_BAT%
set "KIMODO_TEST_MODELS_ROOT=%TEST_MODELS_ROOT%"
set "KIMODO_TEST_SERVER_WINDOW_STYLE=Normal"
set "KIMODO_TEST_OUTPUT=file"
echo [INFO] KIMODO_TEST_SERVER_WINDOW_STYLE=%KIMODO_TEST_SERVER_WINDOW_STYLE%
echo [INFO] KIMODO_TEST_OUTPUT=%KIMODO_TEST_OUTPUT%
call "%DEST_TEST_BAT%"
set "TEST_RC=%ERRORLEVEL%"
echo [INFO] Test exit code: %TEST_RC%
exit /b %TEST_RC%
