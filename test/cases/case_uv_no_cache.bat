@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%\..\.."
for %%I in ("%ROOT_DIR%") do set "ROOT_DIR=%%~fI"
set "COPY_BAT=%ROOT_DIR%\test\copy_to_test_timestamp.bat"
set "RESULT_FILE=%~1"
if not defined RESULT_FILE set "RESULT_FILE=%TEMP%\kimodo_case_uv_no_cache_%RANDOM%%RANDOM%.txt"
set "DEST_INFO_FILE=%TEMP%\kimodo_uv_no_cache_dest_%RANDOM%%RANDOM%.txt"
set "DEFAULT_VENV=C:\nvlab\UnityChanSSU_HDRP\NvlabKimodoQuickServer\kimodo\.venv"

if not exist "%COPY_BAT%" (
  call :write_result FAIL "copy_bat_missing"
  exit /b 1
)

if exist "%DEST_INFO_FILE%" move "%DEST_INFO_FILE%" "%DEST_INFO_FILE%.old.%RANDOM%" >nul 2>nul
set "KIMODO_COPY_ONLY=1"
set "KIMODO_COPY_DEST_FILE=%DEST_INFO_FILE%"
call "%COPY_BAT%"
set "COPY_RC=%ERRORLEVEL%"
set "KIMODO_COPY_ONLY="
set "KIMODO_COPY_DEST_FILE="
if not "%COPY_RC%"=="0" (
  call :write_result FAIL "copy_failed_rc_%COPY_RC%"
  exit /b 1
)
if not exist "%DEST_INFO_FILE%" (
  call :write_result FAIL "copy_dest_info_missing"
  exit /b 1
)

set "RUN_ROOT="
set "TEST_MODELS_ROOT="
for /f "usebackq tokens=1,* delims==" %%A in ("%DEST_INFO_FILE%") do (
  if /I "%%A"=="DEST_DIR" set "RUN_ROOT=%%B"
  if /I "%%A"=="TEST_MODELS_ROOT" set "TEST_MODELS_ROOT=%%B"
)
if not defined RUN_ROOT (
  call :write_result FAIL "run_root_missing"
  exit /b 1
)

set "TEST_BAT=%RUN_ROOT%\example\example_run_server_tpose.bat"
if not exist "%TEST_BAT%" (
  call :write_result FAIL "test_bat_missing"
  exit /b 1
)

set "VENV_PATH=%KIMODO_TEST_VENV_PATH%"
if not defined VENV_PATH set "VENV_PATH=%DEFAULT_VENV%"
if not exist "%VENV_PATH%\Scripts\python.exe" (
  call :write_result FAIL "venv_missing_%VENV_PATH%"
  exit /b 1
)

"%VENV_PATH%\Scripts\python.exe" -c "import torch, kimodo; print('torch='+torch.__version__); print('cuda='+str(torch.version.cuda)); print('kimodo=ok')" >nul 2>nul
if errorlevel 1 (
  call :write_result FAIL "venv_not_usable"
  exit /b 1
)

set "KIMODO_TEST_VENV_PATH=%VENV_PATH%"
set "KIMODO_TEST_WAIT_TIMEOUT_SEC=%KIMODO_TEST_WAIT_TIMEOUT_SEC%"
if not defined KIMODO_TEST_WAIT_TIMEOUT_SEC set "KIMODO_TEST_WAIT_TIMEOUT_SEC=600"
set "KIMODO_TEST_SERVER_WINDOW_STYLE=Normal"
if defined TEST_MODELS_ROOT set "KIMODO_TEST_MODELS_ROOT=%TEST_MODELS_ROOT%"

pushd "%RUN_ROOT%" >nul
call "%TEST_BAT%"
set "RC=%ERRORLEVEL%"
popd >nul

if not "%RC%"=="0" (
  call :write_result FAIL "tpose_failed_rc_%RC%"
  exit /b %RC%
)

call :write_result PASS "ok"
exit /b 0

:write_result
set "STATUS=%~1"
set "DETAIL=%~2"
> "%RESULT_FILE%" (
  echo CASE_NAME=uv_no_cache
  echo STATUS=%STATUS%
  echo DETAIL=%DETAIL%
  echo RUN_ROOT=%RUN_ROOT%
  echo VENV_PATH=%VENV_PATH%
)
exit /b 0
