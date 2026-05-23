@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%~1"
set "WD_PID=%~2"
set "PORT_FILE=%~3"
set "BOOTSTRAP_LOG_PATH=%~4"
set "WATCHDOG_INTERVAL_SEC=%~5"
set "WATCHDOG_MAX_FAILS=%~6"
set "WATCHDOG_CONNECT_TIMEOUT_MS=%~7"
set "WATCHDOG_RUNTIME_INTERVAL_SEC=%~8"
set "WATCHDOG_IDLE_NOLOG_MAX=%~9"
set "BRIDGE_PROBE_PS1=%ROOT_DIR%\bash\bridge_probe.ps1"
set "COMMON_ENV_BAT=%ROOT_DIR%\bash\common_env.bat"
set "RECYCLE_DIR=%ROOT_DIR%\archive\recycle"
set /a WD_FAILS=0
set "WATCHDOG_STARTED_OK=0"
set /a WD_LOG_STALE=0
set "WD_LOG_PATH=%ROOT_DIR%\log\bridge_message.log"
set "WD_LOG_LAST="

echo [INFO] Bridge watchdog started. pid=%WD_PID% startup_interval=%WATCHDOG_INTERVAL_SEC%s startup_max_fails=%WATCHDOG_MAX_FAILS% connect_timeout=%WATCHDOG_CONNECT_TIMEOUT_MS%ms runtime_interval=%WATCHDOG_RUNTIME_INTERVAL_SEC%s idle_nolog_max=%WATCHDOG_IDLE_NOLOG_MAX%

:watchdog_tick
call :is_pid_running "%WD_PID%"
if errorlevel 1 (
  if "%WATCHDOG_STARTED_OK%"=="1" (
    echo [INFO] Bridge process exited. pid=%WD_PID%
    exit /b 0
  )
  echo [ERROR] Bridge process exited before becoming responsive. pid=%WD_PID%
  call :print_bootstrap_hint
  exit /b 1
)

if "%WATCHDOG_STARTED_OK%"=="1" goto watchdog_sleep

call :probe_existing_server
if errorlevel 1 (
  set /a WD_FAILS+=1
  echo [INFO] Waiting bridge ready ^(!WD_FAILS!/%WATCHDOG_MAX_FAILS%^)
  if !WD_FAILS! geq %WATCHDOG_MAX_FAILS% (
    echo [ERROR] Bridge unresponsive for %WATCHDOG_MAX_FAILS% checks during startup. Killing pid=%WD_PID%
    call "%COMMON_ENV_BAT%" :kill_pid_if_kimodo_bridge "%WD_PID%"
    if errorlevel 1 echo [WARN] Skip killing non-kimodo/stale pid=%WD_PID%
    call "%COMMON_ENV_BAT%" :archive_file "%PORT_FILE%" "%RECYCLE_DIR%"
    call :print_bootstrap_hint
    exit /b 1
  )
) else (
  echo [INFO] Bridge became responsive.
  set "WATCHDOG_STARTED_OK=1"
  call :get_file_mtime_epoch "%WD_LOG_PATH%" WD_LOG_LAST
  if not defined WD_LOG_LAST set "WD_LOG_LAST=0"
  set /a WD_FAILS=0
)

:watchdog_sleep
if "%WATCHDOG_STARTED_OK%"=="1" (
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
    if errorlevel 1 echo [WARN] Skip killing non-kimodo/stale pid=%WD_PID%
    call "%COMMON_ENV_BAT%" :archive_file "%PORT_FILE%" "%RECYCLE_DIR%"
    exit /b 0
  )
  call :sleep_seconds "%WATCHDOG_RUNTIME_INTERVAL_SEC%"
) else (
  call :sleep_seconds "%WATCHDOG_INTERVAL_SEC%"
)
goto watchdog_tick

:probe_existing_server
set "PHOST="
set "PPORT="
for /f "usebackq tokens=1,2 delims=:" %%A in ("%PORT_FILE%") do (
  set "PHOST=%%A"
  set "PPORT=%%B"
)
if not defined PHOST exit /b 1
if not defined PPORT exit /b 1

powershell -NoProfile -ExecutionPolicy Bypass -File "%BRIDGE_PROBE_PS1%" -Host "%PHOST%" -Port %PPORT% -ConnectTimeoutMs %WATCHDOG_CONNECT_TIMEOUT_MS% >nul 2>nul
if errorlevel 1 exit /b 1
exit /b 0

:is_pid_running
set "CHECK_PID=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p=Get-Process -Id %CHECK_PID% -ErrorAction SilentlyContinue; if($p){ exit 0 } else { exit 1 }" >nul 2>nul
if errorlevel 1 exit /b 1
exit /b 0

:sleep_seconds
set "SLEEP_SECONDS=%~1"
if not defined SLEEP_SECONDS set "SLEEP_SECONDS=1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Sleep -Seconds %SLEEP_SECONDS%" >nul 2>nul
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

:print_bootstrap_hint
if exist "%BOOTSTRAP_LOG_PATH%" (
  for %%I in ("%BOOTSTRAP_LOG_PATH%") do (
    if %%~zI gtr 0 (
      echo [ERROR] bridge details: %BOOTSTRAP_LOG_PATH%
    ) else (
      echo [WARN] bridge log is empty: %BOOTSTRAP_LOG_PATH%
    )
  )
) else (
  echo [WARN] bridge log missing: %BOOTSTRAP_LOG_PATH%
)
exit /b 0
