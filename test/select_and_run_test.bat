@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "TEST_DIR=%SCRIPT_DIR%"
set "COPY_BAT=%TEST_DIR%\copy_to_test_timestamp.bat"

if not exist "%COPY_BAT%" (
  echo [ERROR] Missing executor: %COPY_BAT%
  exit /b 1
)

set "IDX=0"
echo.
echo ===== Select Test =====
call :add_test_dir "%TEST_DIR%" "test" "copy_to_test_timestamp.bat select_and_run_test.bat"
call :add_test_dir "%TEST_DIR%\cases" "test\cases" ""
if %IDX% LEQ 0 (
  echo [ERROR] No test entries found.
  exit /b 1
)

echo.
set /p "CHOICE=Enter number: "
if not defined CHOICE (
  echo [ERROR] Empty selection.
  exit /b 1
)
for /f "delims=0123456789" %%A in ("%CHOICE%") do (
  echo [ERROR] Invalid selection: %CHOICE%
  exit /b 1
)

call set "SELECTED_TEST_REL=%%ITEM_REL[%CHOICE%]%%"
if not defined SELECTED_TEST_REL (
  echo [ERROR] Selection out of range: %CHOICE%
  exit /b 1
)

echo [INFO] Selected test: %SELECTED_TEST_REL%
call "%COPY_BAT%" "%SELECTED_TEST_REL%"
exit /b %ERRORLEVEL%

:add_test_dir
set "LIST_DIR=%~1"
set "DISPLAY_PREFIX=%~2"
set "SKIP_LIST=%~3"
if not exist "%LIST_DIR%" exit /b 0
for /f "delims=" %%F in ('dir /b /a-d "%LIST_DIR%\*.bat" 2^>nul') do (
  call :should_skip "%%~nxF" "%SKIP_LIST%"
  if errorlevel 1 (
    set /a IDX+=1
    if /I "%DISPLAY_PREFIX%"=="test" (
      set "ITEM_REL[!IDX!]=test\%%F"
    ) else (
      set "ITEM_REL[!IDX!]=test\cases\%%F"
    )
    echo   [!IDX!] %DISPLAY_PREFIX%\%%F
  )
)
exit /b 0

:should_skip
set "CHECK_NAME=%~1"
set "SKIP_LIST=%~2"
if not defined SKIP_LIST exit /b 1
for %%S in (%SKIP_LIST%) do (
  if /I "%CHECK_NAME%"=="%%~S" exit /b 0
)
exit /b 1
