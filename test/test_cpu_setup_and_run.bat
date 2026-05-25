@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%\.."
set "LOG_DIR=%ROOT_DIR%\log"
set "RECYCLE_DIR=%ROOT_DIR%\archive\recycle"
set "PORT_FILE=%ROOT_DIR%\serverport"
set "MODELS_ROOT=C:\nvlab\models~"

if not exist "%ROOT_DIR%\bash\setup.bat" (
  echo [ERROR] setup.bat missing.
  exit /b 1
)
if not exist "%ROOT_DIR%\run_server.bat" (
  echo [ERROR] run_server.bat missing.
  exit /b 1
)
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul
if not exist "%RECYCLE_DIR%" mkdir "%RECYCLE_DIR%" >nul 2>nul

set "SETUP_LOG=%LOG_DIR%\test_cpu_setup.log"
set "RUN_CONSOLE_LOG=%LOG_DIR%\test_cpu_run_console.log"
set "RUN_BRIDGE_LOG=%LOG_DIR%\test_cpu_bridge.log"
set "RUN_PID_FILE=%LOG_DIR%\test_cpu_run.pid"
set "RUN_WRAPPER=%LOG_DIR%\test_cpu_run_wrapper.bat"
set "RUN_WINDOW_TITLE=KIMODO_TEST_CPU_RUN"

call :archive_file "%SETUP_LOG%"
call :archive_file "%RUN_CONSOLE_LOG%"
call :archive_file "%RUN_BRIDGE_LOG%"
call :archive_file "%RUN_PID_FILE%"
call :archive_file "%PORT_FILE%"

echo [STEP] setup cpu mode...
call "%ROOT_DIR%\bash\setup.bat" --device cpu --output file --log "%SETUP_LOG%"
if errorlevel 1 (
  echo [ERROR] setup cpu failed.
  if exist "%SETUP_LOG%" powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%SETUP_LOG%' -Tail 120"
  exit /b 1
)

echo [STEP] run_server cpu mode...
> "%RUN_WRAPPER%" (
  echo @echo off
  echo cd /d "%ROOT_DIR%"
  echo call run_server.bat --model Kimodo-SOMA-RP-v1 --device cpu --models-root "%MODELS_ROOT%" --venv "%ROOT_DIR%\kimodo\.venv" --output file --log "%RUN_BRIDGE_LOG%" ^> "%RUN_CONSOLE_LOG%" 2^>^&1
)
start "%RUN_WINDOW_TITLE%" cmd /k call "%RUN_WRAPPER%"

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
ping 127.0.0.1 -n 2 >nul
set /a WAIT_SEC+=1
if !WAIT_SEC! geq 180 (
  echo [ERROR] timeout waiting serverport.
  call :kill_pid_file "%RUN_PID_FILE%"
  if exist "%RUN_CONSOLE_LOG%" powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%RUN_CONSOLE_LOG%' -Tail 120"
  exit /b 1
)
goto wait_port

:got_port
echo [TEST] target=!HOST!:!PORT!

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; $h='%HOST%'; $p=[int]%PORT%; $c=New-Object Net.Sockets.TcpClient($h,$p); $s=$c.GetStream(); $s.ReadTimeout=1000; $w=New-Object IO.StreamWriter($s); $r=New-Object IO.StreamReader($s); $w.AutoFlush=$true;" ^
  "$w.WriteLine('{""cmd"":""ping""}'); $pong=''; for($i=0;$i -lt 30;$i++){ try { $pong=$r.ReadLine(); if(-not [string]::IsNullOrWhiteSpace($pong)){ break } } catch [System.IO.IOException] { Start-Sleep -Milliseconds 200 } }; if([string]::IsNullOrWhiteSpace($pong)){ throw 'empty pong' };" ^
  "$w.WriteLine('{""cmd"":""generate"",""text"":""tpose"",""duration"":0.4,""diffusion_steps"":1}');" ^
  "$done=''; for($i=0;$i -lt 900;$i++){ try { $line=$r.ReadLine(); if([string]::IsNullOrWhiteSpace($line)){ Start-Sleep -Milliseconds 200; continue }; if($line -match '""status""\s*:\s*""done""'){ $done=$line; break }; if($line -match '""status""\s*:\s*""error""'){ throw ('bridge-error:' + $line) } } catch [System.IO.IOException] { Start-Sleep -Milliseconds 200 } };" ^
  "if([string]::IsNullOrWhiteSpace($done)){ throw 'missing done' };" ^
  "$w.WriteLine('{""cmd"":""quit""}'); $null=$r.ReadLine(); $r.Close(); $w.Close(); $s.Close(); $c.Close();" ^
  "Write-Host '[OK] cpu ping/generate/quit passed.'"
if errorlevel 1 (
  echo [ERROR] cpu tcp smoke failed.
  if exist "%RUN_BRIDGE_LOG%" powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%RUN_BRIDGE_LOG%' -Tail 120"
  call :kill_pid_file "%RUN_PID_FILE%"
  exit /b 1
)

call :wait_exit_or_kill "%RUN_PID_FILE%" 30
echo [OK] test_cpu_setup_and_run passed.
exit /b 0

:wait_exit_or_kill
set "WFILE=%~1"
set /a WMAX=%~2
if not exist "%WFILE%" exit /b 0
set "WPID="
for /f "usebackq delims=" %%A in ("%WFILE%") do (
  if not defined WPID set "WPID=%%A"
)
if not defined WPID exit /b 0
set /a WC=0
:wait_exit_loop
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$pidValue='%WPID%'; if($pidValue -notmatch '^\d+$'){ exit 0 }; $p=Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue; if($null -eq $p){ exit 0 } else { exit 1 }" >nul 2>nul
if not errorlevel 1 (
  call :archive_file "%WFILE%"
  exit /b 0
)
ping 127.0.0.1 -n 2 >nul
set /a WC+=1
if !WC! geq !WMAX! (
  call :kill_pid_file "%WFILE%"
  exit /b 0
)
goto wait_exit_loop

:kill_pid_file
set "KFILE=%~1"
if not exist "%KFILE%" exit /b 0
set "KPID="
for /f "usebackq delims=" %%A in ("%KFILE%") do (
  if not defined KPID set "KPID=%%A"
)
if defined KPID (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='SilentlyContinue'; $pidValue='%KPID%'; if($pidValue -match '^\d+$'){ Stop-Process -Id ([int]$pidValue) -Force -ErrorAction SilentlyContinue }" >nul 2>nul
)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue'; $root=(Resolve-Path -LiteralPath '%ROOT_DIR%').Path; $pat=[regex]::Escape($root); Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { $_.CommandLine -and $_.CommandLine -match 'kimodo\\.bridge\\.bridge_server' -and $_.CommandLine -match $pat } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }" >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue'; Get-CimInstance Win32_Process -Filter \"Name='cmd.exe'\" | Where-Object { $_.CommandLine -and $_.CommandLine -match [regex]::Escape('%RUN_WRAPPER%') } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }" >nul 2>nul
call :archive_file "%KFILE%"
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
