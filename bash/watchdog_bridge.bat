@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%~1"
set "WD_PID=%~2"
set "PORT_FILE=%~3"
set "BOOTSTRAP_LOG_PATH=%~4"
set "WATCHDOG_INTERVAL_SEC=%~5"
set "WATCHDOG_MAX_FAILS=%~6"
set "WATCHDOG_RUNTIME_INTERVAL_SEC=%~7"
set "WATCHDOG_IDLE_NOLOG_MAX=%~8"
set "COMMON_ENV_BAT=%ROOT_DIR%\bash\common_env.bat"
set "WD_LOG_PATH=%ROOT_DIR%\log\bridge_message.log"
set /a WD_FAILS=0
set "WATCHDOG_STARTED_OK=0"
set /a WD_LOG_STALE=0
set "WD_LOG_LAST="

if not defined WATCHDOG_INTERVAL_SEC set "WATCHDOG_INTERVAL_SEC=1"
if not defined WATCHDOG_MAX_FAILS set "WATCHDOG_MAX_FAILS=180"
if not defined WATCHDOG_RUNTIME_INTERVAL_SEC set "WATCHDOG_RUNTIME_INTERVAL_SEC=1"
if not defined WATCHDOG_IDLE_NOLOG_MAX set "WATCHDOG_IDLE_NOLOG_MAX=300"

echo [INFO] Bridge watchdog started. pid=%WD_PID% startup_interval=%WATCHDOG_INTERVAL_SEC%s startup_max_fails=%WATCHDOG_MAX_FAILS% runtime_interval=%WATCHDOG_RUNTIME_INTERVAL_SEC%s idle_nolog_max=%WATCHDOG_IDLE_NOLOG_MAX%

:is_pid_running
set "CHECK_PID=%~1"
if not defined CHECK_PID exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p=Get-Process -Id %CHECK_PID% -ErrorAction SilentlyContinue; if($p){ exit 0 } else { exit 1 }" >nul 2>nul
if errorlevel 1 exit /b 1
exit /b 0

:sleep_seconds
set "SLEEP_SECONDS=%~1"
if not defined SLEEP_SECONDS set "SLEEP_SECONDS=1"
if %SLEEP_SECONDS% LEQ 0 set "SLEEP_SECONDS=1"
set /a SLEEP_PING=%SLEEP_SECONDS%+1
ping 127.0.0.1 -n !SLEEP_PING! >nul
exit /b 0

:get_file_mtime_epoch
set "MTIME_FILE=%~1"
set "MTIME_OUTVAR=%~2"
set "MTIME_VALUE="
if exist "%MTIME_FILE%" (
  for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%MTIME_FILE%'; if(Test-Path -LiteralPath $p){ [int64]([IO.File]::GetLastWriteTimeUtc($p) - [datetime]'1970-01-01').TotalSeconds }"`) do (
    if not defined MTIME_VALUE set "MTIME_VALUE=%%I"
  )
)
set "%MTIME_OUTVAR%=%MTIME_VALUE%"
exit /b 0

:watchdog_tick
call :is_pid_running "%WD_PID%"
if errorlevel 1 (
  if "%WATCHDOG_STARTED_OK%"=="1" (
    echo [INFO] Bridge process/thread invalid. pid=%WD_PID%
    exit /b 0
  ) else (
    echo [ERROR] Bridge process/thread invalid before serverport appeared. pid=%WD_PID%
    exit /b 1
  )
)

if "%WATCHDOG_STARTED_OK%"=="1" goto runtime_tick

if exist "%PORT_FILE%" (
  echo [INFO] serverport detected: %PORT_FILE%
  set "WATCHDOG_STARTED_OK=1"
  call :get_file_mtime_epoch "%WD_LOG_PATH%" WD_LOG_LAST
  if not defined WD_LOG_LAST set "WD_LOG_LAST=0"
  set /a WD_LOG_STALE=0
  call :sleep_seconds "%WATCHDOG_RUNTIME_INTERVAL_SEC%"
  goto watchdog_tick
)

set /a WD_FAILS+=1
echo [INFO] Waiting serverport ^(!WD_FAILS!/%WATCHDOG_MAX_FAILS%^)
if !WD_FAILS! geq %WATCHDOG_MAX_FAILS% (
  echo [ERROR] serverport not found within %WATCHDOG_MAX_FAILS% checks. Killing pid=%WD_PID%
  call "%COMMON_ENV_BAT%" :kill_pid_if_kimodo_bridge "%WD_PID%"
  if errorlevel 1 (
    echo [ERROR] Failed to kill bridge pid=%WD_PID%
    exit /b 1
  )
  exit /b 1
)
call :sleep_seconds "%WATCHDOG_INTERVAL_SEC%"
goto watchdog_tick

:runtime_tick
call :get_file_mtime_epoch "%WD_LOG_PATH%" WD_LOG_NOW
if not defined WD_LOG_NOW set "WD_LOG_NOW=%WD_LOG_LAST%"
if "%WD_LOG_NOW%"=="%WD_LOG_LAST%" (
  set /a WD_LOG_STALE+=1
) else (
  set /a WD_LOG_STALE=0
  set "WD_LOG_LAST=%WD_LOG_NOW%"
)
if !WD_LOG_STALE! geq %WATCHDOG_IDLE_NOLOG_MAX% (
  echo [INFO] No bridge log update for %WATCHDOG_IDLE_NOLOG_MAX% checks. Killing pid=%WD_PID%
  call "%COMMON_ENV_BAT%" :kill_pid_if_kimodo_bridge "%WD_PID%"
  if errorlevel 1 (
    echo [ERROR] Failed to kill bridge pid=%WD_PID%
    exit /b 1
  )
  exit /b 0
)
call :sleep_seconds "%WATCHDOG_RUNTIME_INTERVAL_SEC%"
goto watchdog_tick
