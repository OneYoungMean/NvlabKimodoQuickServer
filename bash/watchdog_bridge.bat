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
set "OWNER_PID=%~9"
set "BRIDGE_PID_FILE=%ROOT_DIR%\.bridge.pid"
set "COMMON_ENV_BAT=%ROOT_DIR%\bash\common_env.bat"
set "WD_LOG_PATH=%ROOT_DIR%\log\bridge_server.log"
set "WATCHDOG_LOG_PATH=%ROOT_DIR%\log\watchdog.log"
set "QUIT_WAIT_SECONDS=3"
set /a WD_FAILS=0
set "WATCHDOG_STARTED_OK=0"
set /a WD_LOG_STALE=0
set "WD_LOG_LAST="

if not defined WATCHDOG_INTERVAL_SEC set "WATCHDOG_INTERVAL_SEC=1"
if not defined WATCHDOG_MAX_FAILS set "WATCHDOG_MAX_FAILS=180"
if not defined WATCHDOG_RUNTIME_INTERVAL_SEC set "WATCHDOG_RUNTIME_INTERVAL_SEC=1"
if not defined WATCHDOG_IDLE_NOLOG_MAX set "WATCHDOG_IDLE_NOLOG_MAX=300"
if not exist "%ROOT_DIR%\log" mkdir "%ROOT_DIR%\log" >nul 2>nul

call :log [INFO] Bridge watchdog started. pid=%WD_PID% owner_pid=%OWNER_PID% startup_interval=%WATCHDOG_INTERVAL_SEC%s startup_max_fails=%WATCHDOG_MAX_FAILS% runtime_interval=%WATCHDOG_RUNTIME_INTERVAL_SEC%s idle_nolog_max=%WATCHDOG_IDLE_NOLOG_MAX%
goto watchdog_tick

:log
set "LOG_LINE=%*"
echo %LOG_LINE%
>> "%WATCHDOG_LOG_PATH%" echo %LOG_LINE%
exit /b 0

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
    call :log [INFO] Bridge process/thread invalid. pid=%WD_PID%
    exit /b 0
  ) else (
    call :log [ERROR] Bridge process/thread invalid before serverport appeared. pid=%WD_PID%
    exit /b 1
  )
)

if defined OWNER_PID (
  call :is_pid_running "%OWNER_PID%"
  if errorlevel 1 (
    call :log [WARN] Owner pid missing during startup. owner_pid=%OWNER_PID% bridge_pid=%WD_PID%
    call :shutdown_bridge_from_watchdog owner_exit_startup
    exit /b !ERRORLEVEL!
  )
)

if "%WATCHDOG_STARTED_OK%"=="1" goto runtime_tick

if exist "%PORT_FILE%" (
  call :log [INFO] serverport detected: %PORT_FILE%
  set "WATCHDOG_STARTED_OK=1"
  call :get_file_mtime_epoch "%WD_LOG_PATH%" WD_LOG_LAST
  if not defined WD_LOG_LAST set "WD_LOG_LAST=0"
  set /a WD_LOG_STALE=0
  call :sleep_seconds "%WATCHDOG_RUNTIME_INTERVAL_SEC%"
  goto watchdog_tick
)

set /a WD_FAILS+=1
call :log [INFO] Waiting serverport ^(!WD_FAILS!/%WATCHDOG_MAX_FAILS%^)
if !WD_FAILS! geq %WATCHDOG_MAX_FAILS% (
  call :log [ERROR] serverport not found within %WATCHDOG_MAX_FAILS% checks. Killing pid=%WD_PID%
  call "%COMMON_ENV_BAT%" :kill_pid_if_kimodo_bridge "%WD_PID%"
  if errorlevel 1 (
    call :log [ERROR] Failed to kill bridge pid=%WD_PID%
    exit /b 1
  )
  call :cleanup_files
  exit /b 1
)
call :sleep_seconds "%WATCHDOG_INTERVAL_SEC%"
goto watchdog_tick

:runtime_tick
if defined OWNER_PID (
  call :is_pid_running "%OWNER_PID%"
  if errorlevel 1 (
    call :log [WARN] Owner pid missing. owner_pid=%OWNER_PID% bridge_pid=%WD_PID%
    call :shutdown_bridge_from_watchdog owner_exit
    exit /b !ERRORLEVEL!
  )
)
call :get_file_mtime_epoch "%WD_LOG_PATH%" WD_LOG_NOW
if not defined WD_LOG_NOW set "WD_LOG_NOW=%WD_LOG_LAST%"
if "%WD_LOG_NOW%"=="%WD_LOG_LAST%" (
  set /a WD_LOG_STALE+=1
) else (
  set /a WD_LOG_STALE=0
  set "WD_LOG_LAST=%WD_LOG_NOW%"
)
if !WD_LOG_STALE! geq %WATCHDOG_IDLE_NOLOG_MAX% (
  call :log [INFO] No bridge log update for %WATCHDOG_IDLE_NOLOG_MAX% checks. Killing pid=%WD_PID%
  call "%COMMON_ENV_BAT%" :kill_pid_if_kimodo_bridge "%WD_PID%"
  if errorlevel 1 (
    call :log [ERROR] Failed to kill bridge pid=%WD_PID%
    exit /b 1
  )
  call :cleanup_files
  exit /b 0
)
call :sleep_seconds "%WATCHDOG_RUNTIME_INTERVAL_SEC%"
goto watchdog_tick

:shutdown_bridge_from_watchdog
set "SHUTDOWN_REASON=%~1"
call :try_send_quit
call :wait_bridge_exit "%QUIT_WAIT_SECONDS%"
if not errorlevel 1 (
  call :cleanup_files
  call :log [INFO] Bridge exited after quit. reason=%SHUTDOWN_REASON%
  exit /b 0
)
call :log [WARN] Bridge still alive after quit, forcing stop. reason=%SHUTDOWN_REASON% pid=%WD_PID%
call "%COMMON_ENV_BAT%" :kill_pid_if_kimodo_bridge "%WD_PID%"
if errorlevel 1 (
  call :log [ERROR] Failed to kill bridge pid=%WD_PID% after quit fallback.
  exit /b 1
)
call :cleanup_files
exit /b 0

:try_send_quit
set "QHOST="
set "QPORT="
if exist "%PORT_FILE%" (
  for /f "usebackq tokens=1,2 delims=:" %%A in ("%PORT_FILE%") do (
    if not defined QHOST set "QHOST=%%A"
    if not defined QPORT set "QPORT=%%B"
  )
)
if not defined QHOST exit /b 0
if not defined QPORT exit /b 0
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue'; $h='%QHOST%'; $p=[int]%QPORT%; $c=$null; try { $c=New-Object Net.Sockets.TcpClient; $iar=$c.BeginConnect($h,$p,$null,$null); if($iar.AsyncWaitHandle.WaitOne(1500)){ $c.EndConnect($iar); $s=$c.GetStream(); $w=New-Object IO.StreamWriter($s); $w.AutoFlush=$true; $w.WriteLine('{""cmd"":""quit""}'); $w.Close(); $s.Close() } } finally { if($c){$c.Close()} }" >nul 2>nul
call :log [INFO] Sent quit to bridge endpoint %QHOST%:%QPORT%
exit /b 0

:wait_bridge_exit
set "WAIT_SECONDS=%~1"
if not defined WAIT_SECONDS set "WAIT_SECONDS=3"
if %WAIT_SECONDS% LEQ 0 set "WAIT_SECONDS=1"
set /a WAIT_TICKS=%WAIT_SECONDS%
:wait_bridge_exit_loop
call :is_pid_running "%WD_PID%"
if errorlevel 1 exit /b 0
if !WAIT_TICKS! LEQ 0 exit /b 1
call :sleep_seconds 1
set /a WAIT_TICKS-=1
goto wait_bridge_exit_loop

:cleanup_files
if exist "%PORT_FILE%" del /f /q "%PORT_FILE%" >nul 2>nul
if defined BRIDGE_PID_FILE if exist "%BRIDGE_PID_FILE%" del /f /q "%BRIDGE_PID_FILE%" >nul 2>nul
exit /b 0
