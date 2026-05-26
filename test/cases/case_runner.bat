@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "TEST_DIR=%SCRIPT_DIR%\.."
for %%I in ("%TEST_DIR%\..") do set "SOURCE_ROOT=%%~fI"
set "COPY_BAT=%TEST_DIR%\copy_to_test_timestamp.bat"
set "DEST_INFO_FILE=%TEMP%\kimodo_case_dest_%RANDOM%%RANDOM%.txt"

if "%~1"=="" (
  echo [ERROR] Missing case name.
  exit /b 1
)
set "CASE_NAME=%~1"
set "INJECT_VAR=%~2"
set "INJECT_VAL=%~3"
set "MODEL_NAME=%~4"
set "HIGHVRAM=%~5"
set "USE_SHARED=%~6"
set "EXPECT_FAIL_RUN1=%~7"
set "RESULT_FILE=%~8"

if not defined HIGHVRAM set "HIGHVRAM=0"
if not defined USE_SHARED set "USE_SHARED=1"
if not defined EXPECT_FAIL_RUN1 set "EXPECT_FAIL_RUN1=1"
if not defined RESULT_FILE set "RESULT_FILE=%TEMP%\kimodo_case_result_%RANDOM%%RANDOM%.txt"

if not exist "%COPY_BAT%" (
  echo [ERROR] copy bat missing: %COPY_BAT%
  call :write_result FAIL "copy_to_test_timestamp_missing"
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

if /I "%CASE_NAME%"=="setup_not_started" (
  if exist "%RUN_ROOT%\.setup.complete" move "%RUN_ROOT%\.setup.complete" "%RUN_ROOT%\archive\recycle\.setup.complete.%RANDOM%" >nul 2>nul
)

set "RUN1_WAIT_TIMEOUT_SEC=%KIMODO_TEST_RUN1_WAIT_TIMEOUT_SEC%"
set "RUN2_WAIT_TIMEOUT_SEC=%KIMODO_TEST_RUN2_WAIT_TIMEOUT_SEC%"
if not defined RUN2_WAIT_TIMEOUT_SEC set "RUN2_WAIT_TIMEOUT_SEC=600"
if not defined RUN1_WAIT_TIMEOUT_SEC (
  if "%EXPECT_FAIL_RUN1%"=="1" (
    set "RUN1_WAIT_TIMEOUT_SEC=180"
  ) else (
    set "RUN1_WAIT_TIMEOUT_SEC=%RUN2_WAIT_TIMEOUT_SEC%"
  )
)

set "KIMODO_TEST_WAIT_TIMEOUT_SEC=%RUN1_WAIT_TIMEOUT_SEC%"
set "KIMODO_TEST_OUTPUT=file"
set "KIMODO_TEST_SERVER_WINDOW_STYLE=Normal"
if "%USE_SHARED%"=="1" (
  set "KIMODO_TEST_MODELS_ROOT=%TEST_MODELS_ROOT%"
  set "KIMODO_MODELS_ROOT=%TEST_MODELS_ROOT%"
) else (
  set "KIMODO_TEST_MODELS_ROOT="
  set "KIMODO_MODELS_ROOT="
)
set "KIMODO_TEST_HIGHVRAM=%HIGHVRAM%"
set "KIMODO_TEST_USE_SHARED_MODELS=%USE_SHARED%"
if defined MODEL_NAME set "KIMODO_TEST_MODEL=%MODEL_NAME%"
if defined INJECT_VAR if defined INJECT_VAL set "%INJECT_VAR%=%INJECT_VAL%"

pushd "%RUN_ROOT%" >nul
call "%TEST_BAT%"
set "RC1=%ERRORLEVEL%"
popd >nul

if defined INJECT_VAR set "%INJECT_VAR%="

set "KIMODO_TEST_WAIT_TIMEOUT_SEC=%RUN2_WAIT_TIMEOUT_SEC%"

set "RUN1_OK=0"
if "%RC1%"=="0" set "RUN1_OK=1"
if "%EXPECT_FAIL_RUN1%"=="1" (
  if "%RUN1_OK%"=="1" (
    rem tolerated
  )
) else (
  if not "%RUN1_OK%"=="1" (
    call :write_result FAIL "run1_unexpected_fail_rc_%RC1%"
    exit /b 1
  )
)

if "%EXPECT_FAIL_RUN1%"=="1" (
  if exist "%RUN_ROOT%\bash\setup.bat" (
    if not exist "%RUN_ROOT%\archive\recycle" mkdir "%RUN_ROOT%\archive\recycle" >nul 2>nul
    if exist "%RUN_ROOT%\.setup.lock" (
      move "%RUN_ROOT%\.setup.lock" "%RUN_ROOT%\archive\recycle\.setup.lock.recover.%RANDOM%%RANDOM%" >nul 2>nul
    )
    if exist "%RUN_ROOT%\log\example_run_server_tpose.pid" (
      set "RECOVER_PID="
      for /f "usebackq delims=" %%P in ("%RUN_ROOT%\log\example_run_server_tpose.pid") do (
        if not defined RECOVER_PID set "RECOVER_PID=%%P"
      )
      if defined RECOVER_PID (
        powershell -NoProfile -ExecutionPolicy Bypass -Command ^
          "$ErrorActionPreference='SilentlyContinue'; $pidValue='%RECOVER_PID%'; if($pidValue -match '^\d+$'){ Stop-Process -Id ([int]$pidValue) -Force -ErrorAction SilentlyContinue }" >nul 2>nul
      )
    )
    if exist "%RUN_ROOT%\serverport" (
      powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "$ErrorActionPreference='SilentlyContinue'; Remove-Item -LiteralPath '%RUN_ROOT%\\serverport' -Force -ErrorAction SilentlyContinue" >nul 2>nul
    )
    pushd "%RUN_ROOT%" >nul
    call "%RUN_ROOT%\bash\setup.bat" --force --output file --log "%RUN_ROOT%\log\setup.log"
    set "RECOVER_SETUP_RC=!ERRORLEVEL!"
    popd >nul
    if not "!RECOVER_SETUP_RC!"=="0" (
      call :write_result FAIL "recover_setup_failed_rc_!RECOVER_SETUP_RC!"
      exit /b 1
    )
  )
)

pushd "%RUN_ROOT%" >nul
call "%TEST_BAT%"
set "RC2=%ERRORLEVEL%"
popd >nul

if "%RC2%"=="0" (
  call :write_result PASS "ok"
  exit /b 0
)

call :write_result FAIL "run2_failed_rc_%RC2%"
exit /b 1

:write_result
set "STATUS=%~1"
set "DETAIL=%~2"
> "%RESULT_FILE%" (
  echo CASE_NAME=%CASE_NAME%
  echo STATUS=%STATUS%
  echo DETAIL=%DETAIL%
  echo RUN_ROOT=%RUN_ROOT%
)
exit /b 0



