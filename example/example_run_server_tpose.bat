@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%\.."
set "LOG_DIR=%ROOT_DIR%\log"

set "LAUNCHER=%ROOT_DIR%\run_server.bat"
set "MODEL=Kimodo-SOMA-RP-v1"
set "PORT_FILE=%ROOT_DIR%\serverport"
set "RUN_LOG=%LOG_DIR%\example_run_server_tpose.log"
set "CLIENT_LOG=%LOG_DIR%\example_run_server_tpose_client.log"
set "CLIENT_PS1=%SCRIPT_DIR%\example_run_server_tpose_client.ps1"
set "SETUP_LOCK=%ROOT_DIR%\.setup_new.lock"
set "SETUP_SENTINEL=%ROOT_DIR%\.setup_new_complete"
set "SERVER_STARTED=0"
set "SERVER_PID_FILE=%TEMP%\kimodo_test_server_pid_%RANDOM%%RANDOM%.txt"
set "RECYCLE_DIR=%ROOT_DIR%\archive\recycle"

set "OUTPUT_MODE=%KIMODO_TEST_OUTPUT%"
if not defined OUTPUT_MODE set "OUTPUT_MODE=file"
for /f "tokens=* delims= " %%A in ("%OUTPUT_MODE%") do set "OUTPUT_MODE=%%A"
for /l %%I in (1,1,4) do if "!OUTPUT_MODE:~-1!"==" " set "OUTPUT_MODE=!OUTPUT_MODE:~0,-1!"
set "WAIT_TIMEOUT_SEC="

if not exist "%LAUNCHER%" (
  echo [ERROR] run_server not found: %LAUNCHER%
  exit /b 1
)
if not exist "%CLIENT_PS1%" (
  echo [ERROR] example client not found: %CLIENT_PS1%
  exit /b 1
)
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul

echo [TEST] ROOT_DIR=%ROOT_DIR%
echo [TEST] MODEL=%MODEL%
echo [TEST] MODE=%OUTPUT_MODE%

call :decide_wait_timeout
echo [TEST] WAIT_TIMEOUT_SEC=%WAIT_TIMEOUT_SEC%

call :wait_setup_lock_clear
if errorlevel 1 exit /b 1

call :archive_file "%PORT_FILE%"
call :archive_file "%CLIENT_LOG%"

call :launch_server_background
if errorlevel 1 (
  echo [ERROR] Failed to launch run_server in background.
  exit /b 1
)

set "HOST="
set "PORT="
set /a WAIT_SEC=0
:wait_port
if exist "%PORT_FILE%" (
  for /f "usebackq tokens=1,2 delims=:" %%A in ("%PORT_FILE%") do (
    set "HOST=%%A"
    set "PORT=%%B"
  )
)
if defined HOST if defined PORT goto got_port

call :sleep_1s_or_cancel
if errorlevel 1 goto user_cancelled
set /a WAIT_SEC+=1
if !WAIT_SEC! geq !WAIT_TIMEOUT_SEC! (
  echo [ERROR] Timeout waiting for serverport file: %PORT_FILE%
  if /I "%OUTPUT_MODE%"=="file" if exist "%RUN_LOG%" (
    echo [TEST] run_server log tail:
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%RUN_LOG%'; if(Test-Path -LiteralPath $p){Get-Content -LiteralPath $p -Tail 80}"
  )
  exit /b 1
)
goto wait_port

:got_port
echo [TEST] TARGET=!HOST!:!PORT!

call :archive_file "%CLIENT_LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; $hostName='%HOST%'; $port=%PORT%; $prompt='tpose'; $duration=5.0; $seed=42; $steps=100; $constraints=''; $ps1='%CLIENT_PS1%'; $log='%CLIENT_LOG%'; & $ps1 -HostName $hostName -Port $port -Prompt $prompt -Duration $duration -Seed $seed -DiffusionSteps $steps -ConstraintsJson $constraints 2>&1 | Tee-Object -FilePath $log -Append"
set "EXIT_CODE=%ERRORLEVEL%"

echo [TEST] Client exit code: %EXIT_CODE%
if not "%EXIT_CODE%"=="0" (
  if /I "%OUTPUT_MODE%"=="file" if exist "%CLIENT_LOG%" (
    echo [TEST] client log tail:
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%CLIENT_LOG%'; if(Test-Path -LiteralPath $p){Get-Content -LiteralPath $p -Tail 80}"
  )
  call :try_kill_server_pid
  exit /b %EXIT_CODE%
)

echo [OK] example_run_server_tpose passed.
if /I "%OUTPUT_MODE%"=="file" if exist "%CLIENT_LOG%" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$p='%CLIENT_LOG%'; $done=Get-Content -LiteralPath $p | Where-Object { $_ -match '\"status\": \"done\"' } | Select-Object -Last 1; if($done){ Write-Host '[TEST] done payload detected.' }"
)
call :try_kill_server_pid
exit /b 0

:decide_wait_timeout
if defined KIMODO_TEST_WAIT_TIMEOUT_SEC (
  set "WAIT_TIMEOUT_SEC=%KIMODO_TEST_WAIT_TIMEOUT_SEC%"
  exit /b 0
)
set "WAIT_TIMEOUT_SEC=600"
exit /b 0

:wait_setup_lock_clear
if not exist "%SETUP_LOCK%" exit /b 0
set /a LOCK_WAIT=0
:wait_setup_loop
if not exist "%SETUP_LOCK%" exit /b 0
call :sleep_1s_or_cancel
if errorlevel 1 goto user_cancelled
set /a LOCK_WAIT+=1
if !LOCK_WAIT! geq !WAIT_TIMEOUT_SEC! (
  echo [ERROR] Timeout waiting setup lock release: %SETUP_LOCK%
  exit /b 1
)
goto wait_setup_loop

:sleep_1s_or_cancel
ping 127.0.0.1 -n 2 >nul
if errorlevel 1 exit /b 1
exit /b 0

:user_cancelled
echo [WARN] Interrupted by user ^(Ctrl+C^). Trying to stop server...
if "%SERVER_STARTED%"=="1" call :try_quit_if_running
call :try_kill_server_pid
exit /b 130

:try_quit_if_running
if not exist "%PORT_FILE%" exit /b 0
set "QHOST="
set "QPORT="
for /f "usebackq tokens=1,2 delims=:" %%A in ("%PORT_FILE%") do (
  set "QHOST=%%A"
  set "QPORT=%%B"
)
if not defined QHOST exit /b 0
if not defined QPORT exit /b 0
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue'; $h='%QHOST%'; $p=[int]%QPORT%; $c=New-Object Net.Sockets.TcpClient($h,$p); $s=$c.GetStream(); $w=New-Object IO.StreamWriter($s); $w.AutoFlush=$true; $w.WriteLine('{""cmd"":""quit""}'); $w.Close(); $s.Close(); $c.Close();" >nul 2>nul
exit /b 0

:launch_server_background
call :archive_file "%SERVER_PID_FILE%"
set "LAUNCH_ARGS=--model \"%MODEL%\" --output console"
if /I "%OUTPUT_MODE%"=="file" set "LAUNCH_ARGS=--model \"%MODEL%\" --output file --log \"%RUN_LOG%\""
set "LAUNCH_PS=$ErrorActionPreference='Stop'; $launcher='%LAUNCHER%'; $wd='%ROOT_DIR%'; $args='%LAUNCH_ARGS%'; $cmdArg='/d /c ""' + $launcher + '"" ' + $args; $p=Start-Process -FilePath 'cmd.exe' -ArgumentList $cmdArg -WorkingDirectory $wd -PassThru; Set-Content -LiteralPath '%SERVER_PID_FILE%' -Value $p.Id -Encoding ASCII"
call powershell -NoProfile -ExecutionPolicy Bypass -Command "%LAUNCH_PS%"
if errorlevel 1 (
  echo [ERROR] launch_server_background failed.
  exit /b 1
)
set "SERVER_STARTED=1"
exit /b 0

:try_kill_server_pid
if not exist "%SERVER_PID_FILE%" exit /b 0
set "SPID="
for /f "usebackq delims=" %%A in ("%SERVER_PID_FILE%") do (
  if not defined SPID set "SPID=%%A"
)
if defined SPID (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='SilentlyContinue'; $pidValue='%SPID%'; if($pidValue -match '^\d+$'){ Stop-Process -Id ([int]$pidValue) -Force -ErrorAction SilentlyContinue }" >nul 2>nul
)
call :archive_file "%SERVER_PID_FILE%"
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
