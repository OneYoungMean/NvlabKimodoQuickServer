@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%\.."
set "LAUNCHER=%ROOT_DIR%\run_server.bat"
set "CLIENT_PS1=%SCRIPT_DIR%\example_run_server_tpose_client.ps1"
set "PORT_FILE=%ROOT_DIR%\serverport"
set "PID_FILE=%ROOT_DIR%\log\example_run_server_tpose.pid"
set "RECYCLE_DIR=%ROOT_DIR%\archive\recycle"

set "MODEL=Kimodo-SOMA-RP-v1"
if defined KIMODO_TEST_MODEL set "MODEL=%KIMODO_TEST_MODEL%"
set "DEVICE=%KIMODO_TEST_DEVICE%"
if not defined DEVICE set "DEVICE=cuda"
set "VENV_PATH=%KIMODO_TEST_VENV_PATH%"
if not defined VENV_PATH set "VENV_PATH=%ROOT_DIR%\kimodo\.venv"

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

echo [TEST] ROOT_DIR=%ROOT_DIR%
echo [TEST] MODEL=%MODEL%
echo [TEST] DEVICE=%DEVICE%
echo [TEST] VENV_PATH=%VENV_PATH%
echo [TEST] OUTPUT=console

call :archive_file "%PORT_FILE%"
call :archive_file "%PID_FILE%"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; $args=@('/d','/c','run_server.bat','--model','%MODEL%','--device','%DEVICE%','--venv','%VENV_PATH%','--output','console'); $p=Start-Process -FilePath 'cmd.exe' -ArgumentList $args -WorkingDirectory '%ROOT_DIR%' -WindowStyle Normal -PassThru; Set-Content -LiteralPath '%PID_FILE%' -Value $p.Id -Encoding ASCII"
if errorlevel 1 (
  echo [ERROR] failed to launch run_server.
  exit /b 1
)

if not exist "%PORT_FILE%" (
  echo [ERROR] serverport missing: %PORT_FILE%
  call :kill_pid
  exit /b 1
)
set "HOST="
set "PORT="
for /f "usebackq tokens=1,2 delims=:" %%A in ("%PORT_FILE%") do (
  set "HOST=%%A"
  set "PORT=%%B"
)
if not defined HOST (
  echo [ERROR] invalid serverport content.
  call :kill_pid
  exit /b 1
)
if not defined PORT (
  echo [ERROR] invalid serverport content.
  call :kill_pid
  exit /b 1
)
echo [TEST] TARGET=!HOST!:!PORT!

powershell -NoProfile -ExecutionPolicy Bypass -File "%CLIENT_PS1%" -HostName "!HOST!" -Port !PORT! -Prompt "tpose" -Duration 5.0 -Seed 42 -DiffusionSteps 100 -ConstraintsJson ""
set "RC=%ERRORLEVEL%"
echo [TEST] client exit code: %RC%

call :quit_and_wait
if not "%RC%"=="0" exit /b %RC%
echo [OK] example_run_server_tpose passed.
exit /b 0

:quit_and_wait
if exist "%PORT_FILE%" (
  set "QHOST="
  set "QPORT="
  for /f "usebackq tokens=1,2 delims=:" %%A in ("%PORT_FILE%") do (
    set "QHOST=%%A"
    set "QPORT=%%B"
  )
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
move "%ARCHIVE_TARGET%" "%DEST%" >nul 2>nul
exit /b 0
