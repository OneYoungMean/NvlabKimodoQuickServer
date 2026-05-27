@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%\.."
set "LAUNCHER=%ROOT_DIR%\run_server.bat"
set "CLIENT_PS1=%SCRIPT_DIR%\example_run_server_tpose_client.ps1"
set "PORT_FILE=%ROOT_DIR%\serverport"
set "PID_FILE=%ROOT_DIR%\log\example_run_server_tpose.pid"
set "SERVER_LOG=%ROOT_DIR%\log\example_run_server_tpose_server.log"
set "BRIDGE_SERVER_LOG=%ROOT_DIR%\log\bridge_server.log"
set "BRIDGE_MESSAGE_LOG=%ROOT_DIR%\log\bridge_message.log"
set "RECYCLE_DIR=%ROOT_DIR%\archive\recycle"
set "WAIT_TIMEOUT_SEC=%KIMODO_TEST_WAIT_TIMEOUT_SEC%"
if not defined WAIT_TIMEOUT_SEC set "WAIT_TIMEOUT_SEC=600"
set "WAIT_HINT_INTERVAL_SEC=10"

set "MODEL=Kimodo-SOMA-RP-v1"
if defined KIMODO_TEST_MODEL set "MODEL=%KIMODO_TEST_MODEL%"
set "DEVICE=%KIMODO_TEST_DEVICE%"
if not defined DEVICE set "DEVICE=cuda"
set "MODELS_ROOT=%KIMODO_TEST_MODELS_ROOT%"
set "VENV_PATH=%KIMODO_TEST_VENV_PATH%"
set "USE_VENV_ARG=0"
if defined VENV_PATH (
  if exist "%VENV_PATH%\Scripts\python.exe" (
    set "USE_VENV_ARG=1"
  ) else (
    echo [ERROR] KIMODO_TEST_VENV_PATH set but invalid: %VENV_PATH%\Scripts\python.exe
    exit /b 1
  )
)

if not exist "%LAUNCHER%" (
  echo [ERROR] run_server.bat not found: %LAUNCHER%
  exit /b 1
)
if not exist "%CLIENT_PS1%" (
  echo [ERROR] client ps1 not found: %CLIENT_PS1%
  exit /b 1
)
if not exist "%ROOT_DIR%\log" mkdir "%ROOT_DIR%\log" >nul 2>nul
if not exist "%RECYCLE_DIR%" mkdir "%RECYCLE_DIR%" >nul 2>nul

if defined KIMODO_TEST_DEVICE (
  if /I "%KIMODO_TEST_DEVICE%"=="cpu" (
    if defined KIMODO_SETUP_DEVICE (
      if /I not "%KIMODO_SETUP_DEVICE%"=="cpu" (
        echo [WARN] Aligning KIMODO_SETUP_DEVICE to cpu for test consistency.
      )
    )
    set "KIMODO_SETUP_DEVICE=cpu"
  )
)

echo [TEST] ROOT_DIR=%ROOT_DIR%
echo [TEST] MODEL=%MODEL%
echo [TEST] DEVICE=%DEVICE%
if defined MODELS_ROOT (
  echo [TEST] MODELS_ROOT=%MODELS_ROOT%
) else (
  echo [TEST] MODELS_ROOT=^<default^>
)
if "%USE_VENV_ARG%"=="1" (
  echo [TEST] VENV_PATH=%VENV_PATH%
) else (
  echo [TEST] VENV_PATH=^<auto^>
)
echo [TEST] OUTPUT=file

call :archive_file "%PORT_FILE%"
call :archive_file "%PID_FILE%"
call :archive_file "%SERVER_LOG%"
if exist "%BRIDGE_SERVER_LOG%" call :archive_file "%BRIDGE_SERVER_LOG%"
if exist "%BRIDGE_MESSAGE_LOG%" call :archive_file "%BRIDGE_MESSAGE_LOG%"

set "LAUNCH_PS_CMD=$ErrorActionPreference='Stop'; $args=@('/d','/c','run_server.bat','--model','%MODEL%','--device','%DEVICE%');"
if defined MODELS_ROOT call set "LAUNCH_PS_CMD=%%LAUNCH_PS_CMD%% $args += @('--models-root','%MODELS_ROOT%');"
if "%USE_VENV_ARG%"=="1" call set "LAUNCH_PS_CMD=%%LAUNCH_PS_CMD%% $args += @('--venv','%VENV_PATH%');"
call set "LAUNCH_PS_CMD=%%LAUNCH_PS_CMD%% $args += @('--output','file','--log','%SERVER_LOG%');"
set "LAUNCH_PS_CMD=!LAUNCH_PS_CMD! $p=Start-Process -FilePath 'cmd.exe' -ArgumentList $args -WorkingDirectory '%ROOT_DIR%' -WindowStyle Normal -PassThru; Set-Content -LiteralPath '%PID_FILE%' -Value $p.Id -Encoding ASCII"

powershell -NoProfile -ExecutionPolicy Bypass -Command "!LAUNCH_PS_CMD!"
if errorlevel 1 (
  echo [ERROR] failed to launch run_server.
  exit /b 1
)

set /a WAIT_SEC=0
:wait_serverport
if exist "%PORT_FILE%" (
  call :read_serverport_retry
  if not errorlevel 1 goto got_serverport
)
call :read_endpoint_from_logs
if not errorlevel 1 goto got_serverport
call :is_runserver_alive
if errorlevel 1 (
  set "RUNSERVER_EXITED=1"
)
ping 127.0.0.1 -n 2 >nul
set /a WAIT_SEC+=1
set /a WAIT_MOD=WAIT_SEC %% WAIT_HINT_INTERVAL_SEC
if !WAIT_MOD! equ 0 (
  if defined RUNSERVER_EXITED (
    echo [TEST] waiting serverport... !WAIT_SEC!/%WAIT_TIMEOUT_SEC%s ^(run_server exited, waiting for bridge handoff^)
  ) else (
    echo [TEST] waiting serverport... !WAIT_SEC!/%WAIT_TIMEOUT_SEC%s
  )
)
if !WAIT_SEC! geq %WAIT_TIMEOUT_SEC% (
  if defined RUNSERVER_EXITED (
    echo [ERROR] serverport missing after !WAIT_SEC!s: %PORT_FILE% ^(run_server exited during startup^)
  ) else (
    echo [ERROR] serverport missing after !WAIT_SEC!s: %PORT_FILE%
  )
  call :dump_startup_logs
  call :kill_pid
  exit /b 1
)
goto wait_serverport

:got_serverport
if not defined HOST (
  echo [ERROR] endpoint host is empty.
  call :dump_startup_logs
  call :kill_pid
  exit /b 1
)
if not defined PORT (
  echo [ERROR] endpoint port is empty.
  call :dump_startup_logs
  call :kill_pid
  exit /b 1
)
echo [TEST] TARGET=!HOST!:!PORT!

powershell -NoProfile -ExecutionPolicy Bypass -File "%CLIENT_PS1%" -HostName "!HOST!" -Port !PORT! -Prompt "tpose" -Duration 5.0 -Seed 42 -DiffusionSteps 100 -ConstraintsJson ""
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  call :is_runserver_alive
  if not errorlevel 1 (
    echo [WARN] first client attempt failed, retry once...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%CLIENT_PS1%" -HostName "!HOST!" -Port !PORT! -Prompt "tpose" -Duration 5.0 -Seed 42 -DiffusionSteps 100 -ConstraintsJson ""
    set "RC=%ERRORLEVEL%"
  )
)
echo [TEST] client exit code: %RC%

call :quit_and_wait
if not "%RC%"=="0" exit /b %RC%
echo [OK] example_run_server_tpose passed.
exit /b 0

:quit_and_wait
if exist "%PORT_FILE%" (
  call :read_serverport_retry
  set "QHOST=!HOST!"
  set "QPORT=!PORT!"
  if defined QHOST if defined QPORT (
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$ErrorActionPreference='SilentlyContinue'; $h='%QHOST%'; $p=[int]%QPORT%; $c=New-Object Net.Sockets.TcpClient; $iar=$c.BeginConnect($h,$p,$null,$null); if($iar.AsyncWaitHandle.WaitOne(1500)){ $c.EndConnect($iar); $s=$c.GetStream(); $w=New-Object IO.StreamWriter($s); $w.AutoFlush=$true; $w.WriteLine('{""cmd"":""quit""}'); $w.Close(); $s.Close() }; $c.Close();" >nul 2>nul
  )
)
call :wait_pid_or_kill
exit /b 0

:wait_pid_or_kill
if not exist "%PID_FILE%" exit /b 0
set "SPID="
for /f "usebackq delims=" %%A in ("%PID_FILE%") do (
  if not defined SPID set "SPID=%%A"
)
if not defined SPID (
  call :archive_file "%PID_FILE%"
  exit /b 0
)
set /a WAIT_SEC=0
:wait_loop
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$pidValue='%SPID%'; if($pidValue -notmatch '^\d+$'){ exit 0 }; $p=Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue; if($null -eq $p){ exit 0 } else { exit 1 }" >nul 2>nul
if not errorlevel 1 (
  call :archive_file "%PID_FILE%"
  exit /b 0
)
ping 127.0.0.1 -n 2 >nul
set /a WAIT_SEC+=1
if !WAIT_SEC! geq 15 (
  call :kill_pid
  exit /b 0
)
goto wait_loop

:kill_pid
if not exist "%PID_FILE%" exit /b 0
set "KPID="
for /f "usebackq delims=" %%A in ("%PID_FILE%") do (
  if not defined KPID set "KPID=%%A"
)
if defined KPID (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='SilentlyContinue'; $pidValue='%KPID%'; if($pidValue -match '^\d+$'){ Stop-Process -Id ([int]$pidValue) -Force -ErrorAction SilentlyContinue }" >nul 2>nul
)
call :archive_file "%PID_FILE%"
exit /b 0

:archive_file
set "ARCHIVE_TARGET=%~1"
if not exist "%ARCHIVE_TARGET%" exit /b 0
set "TS=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "TS=%TS: =0%"
set "BASE=%~nx1"
set "DEST=%RECYCLE_DIR%\%BASE%.%TS%.%RANDOM%"
set /a ARCH_TRY=0
:archive_retry
move "%ARCHIVE_TARGET%" "%DEST%" >nul 2>nul
if not errorlevel 1 exit /b 0
if not exist "%ARCHIVE_TARGET%" exit /b 0
set /a ARCH_TRY+=1
if !ARCH_TRY! geq 5 (
  echo [WARN] archive skip ^(file busy^): %ARCHIVE_TARGET%
  exit /b 0
)
ping 127.0.0.1 -n 2 >nul
goto archive_retry
exit /b 0

:read_serverport_retry
set "HOST="
set "PORT="
for /l %%R in (1,1,40) do (
  if not exist "%PORT_FILE%" exit /b 1
  set "HOST="
  set "PORT="
  for /f "usebackq tokens=1,2 delims=:" %%A in ("%PORT_FILE%") do (
    set "HOST=%%A"
    set "PORT=%%B"
  )
  if defined HOST if defined PORT exit /b 0
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Sleep -Milliseconds 150" >nul 2>nul
)
exit /b 1

:read_endpoint_from_logs
set "HOST="
set "PORT="
for /f "usebackq tokens=1,2 delims=:" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; $paths=@('%BRIDGE_SERVER_LOG%','%BRIDGE_MESSAGE_LOG%'); $h=''; $pt=''; foreach($p in $paths){ if(-not (Test-Path -LiteralPath $p)){ continue }; $lines=Get-Content -LiteralPath $p -Tail 240; for($i=$lines.Count-1; $i -ge 0; $i--){ $line=[string]$lines[$i]; if($line -match 'ready host=(?<host>\\S+) port=(?<port>\\d+)'){ $h=$Matches['host']; $pt=$Matches['port']; break } }; if($h -and $pt){ break } }; if($h -and $pt){ Write-Output ($h + ':' + $pt) }"`) do (
  if not defined HOST set "HOST=%%A"
  if not defined PORT set "PORT=%%B"
)
if defined HOST if defined PORT (
  echo [TEST] endpoint from bridge log: !HOST!:!PORT!
  exit /b 0
)
exit /b 1

:is_runserver_alive
if not exist "%PID_FILE%" exit /b 1
set "RPID="
for /f "usebackq delims=" %%A in ("%PID_FILE%") do (
  if not defined RPID set "RPID=%%A"
)
if not defined RPID exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$pidValue='%RPID%'; if($pidValue -notmatch '^\d+$'){ exit 1 }; $p=Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue; if($null -eq $p){ exit 1 } else { exit 0 }" >nul 2>nul
if errorlevel 1 exit /b 1
exit /b 0

:dump_startup_logs
echo [DIAG] tail: %ROOT_DIR%\log\setup.log
powershell -NoProfile -ExecutionPolicy Bypass -Command "if(Test-Path '%ROOT_DIR%\log\setup.log'){Get-Content '%ROOT_DIR%\log\setup.log' -Tail 40}" 2>nul
echo [DIAG] tail: %ROOT_DIR%\log\download_model.log
powershell -NoProfile -ExecutionPolicy Bypass -Command "if(Test-Path '%ROOT_DIR%\log\download_model.log'){Get-Content '%ROOT_DIR%\log\download_model.log' -Tail 40}" 2>nul
echo [DIAG] tail: %ROOT_DIR%\log\bridge_server.log
powershell -NoProfile -ExecutionPolicy Bypass -Command "if(Test-Path '%ROOT_DIR%\log\bridge_server.log'){Get-Content '%ROOT_DIR%\log\bridge_server.log' -Tail 40}" 2>nul
echo [DIAG] tail: %SERVER_LOG%
powershell -NoProfile -ExecutionPolicy Bypass -Command "if(Test-Path '%SERVER_LOG%'){Get-Content '%SERVER_LOG%' -Tail 40}" 2>nul
exit /b 0
