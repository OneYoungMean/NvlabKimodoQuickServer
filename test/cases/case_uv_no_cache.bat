@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "ROOT_DIR=%SCRIPT_DIR%\..\.."
for %%I in ("%ROOT_DIR%") do set "ROOT_DIR=%%~fI"
set "DEFAULT_VENV=C:\nvlab\UnityChanSSU_HDRP\NvlabKimodoQuickServer\kimodo\.venv"
set "RESULT_FILE=%~1"
if not defined RESULT_FILE set "RESULT_FILE=%TEMP%\kimodo_case_uv_no_cache_%RANDOM%%RANDOM%.txt"
set "RUN_ROOT=%ROOT_DIR%"
set "VENV_PATH=%KIMODO_TEST_VENV_PATH%"
if not defined VENV_PATH set "VENV_PATH=%DEFAULT_VENV%"
set "TEST_BAT=%ROOT_DIR%\example\example_run_server_tpose.bat"
set "TEST_MODELS_ROOT=%KIMODO_TEST_MODELS_ROOT%"

if not exist "%VENV_PATH%\Scripts\python.exe" (
  call :write_result FAIL "venv_missing_%VENV_PATH%"
  exit /b 1
)
if not exist "%TEST_BAT%" (
  call :write_result FAIL "test_bat_missing"
  exit /b 1
)

"%VENV_PATH%\Scripts\python.exe" -c "import torch, kimodo; print('torch='+torch.__version__); print('cuda='+str(torch.version.cuda)); print('kimodo=ok')" >nul 2>nul
if errorlevel 1 (
  call :write_result FAIL "venv_not_usable"
  exit /b 1
)

set "KIMODO_TEST_VENV_PATH=%VENV_PATH%"
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
