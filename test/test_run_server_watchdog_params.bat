@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%\.."
set "LOG_DIR=%ROOT_DIR%\log"
set "ARCHIVE_DIR=%ROOT_DIR%\archive\recycle"
set "PORT_FILE=%ROOT_DIR%\serverport"
set "MODELS_ROOT=C:\nvlab\models~"
set "VENV_PATH=%KIMODO_TEST_VENV_PATH%"
if not defined VENV_PATH (
  if exist "%ROOT_DIR%\kimodo\.venv\Scripts\python.exe" set "VENV_PATH=%ROOT_DIR%\kimodo\.venv"
)

if not exist "%ROOT_DIR%\run_server.bat" (
  echo [ERROR] run_server.bat not found under: %ROOT_DIR%
  exit /b 1
)
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul
if not exist "%ARCHIVE_DIR%" mkdir "%ARCHIVE_DIR%" >nul 2>nul

call :archive_file "%PORT_FILE%"

set "FAIL_COUNT=0"
call :run_case "defaults" "" "" "" "" ""
call :run_case "custom_fast" "2" "12" "500" "" ""
call :run_case "custom_runtime_idle" "1" "30" "700" "2" "15"

if not "%FAIL_COUNT%"=="0" (
  echo [RESULT] FAILED cases=%FAIL_COUNT%
  exit /b 1
)
echo [RESULT] ALL PASSED
exit /b 0

:run_case
set "CASE_NAME=%~1"
set "CASE_STARTUP_INTERVAL=%~2"
set "CASE_MAX_FAILS=%~3"
set "CASE_CONNECT_MS=%~4"
set "CASE_RUNTIME_INTERVAL=%~5"
set "CASE_IDLE_NOLOG_MAX=%~6"

echo [CASE] %CASE_NAME%

set "CASE_CONSOLE_LOG=%LOG_DIR%\test_watchdog_%CASE_NAME%_console.log"
set "CASE_BRIDGE_LOG=%LOG_DIR%\test_watchdog_%CASE_NAME%_bridge.log"
set "CASE_PID_FILE=%LOG_DIR%\test_watchdog_%CASE_NAME%_run_server.pid"

call :archive_file "%CASE_CONSOLE_LOG%"
call :archive_file "%CASE_BRIDGE_LOG%"
call :archive_file "%CASE_PID_FILE%"
call :archive_file "%PORT_FILE%"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$root='%ROOT_DIR%';" ^
  "$consoleLog='%CASE_CONSOLE_LOG%';" ^
  "$bridgeLog='%CASE_BRIDGE_LOG%';" ^
  "$pidFile='%CASE_PID_FILE%';" ^
  "$argList=@('/d','/c','run_server.bat','--model','Kimodo-SOMA-RP-v1','--models-root','%MODELS_ROOT%','--output','file','--log',$bridgeLog); if('%VENV_PATH%' -ne ''){ $argList += @('--venv','%VENV_PATH%') };" ^
  "$envMap=@{};" ^
  "if('%CASE_STARTUP_INTERVAL%' -ne ''){ $envMap['KIMODO_WATCHDOG_STARTUP_INTERVAL_SEC']='%CASE_STARTUP_INTERVAL%' } else { Remove-Item Env:KIMODO_WATCHDOG_STARTUP_INTERVAL_SEC -ErrorAction SilentlyContinue };" ^
  "if('%CASE_MAX_FAILS%' -ne ''){ $envMap['KIMODO_WATCHDOG_STARTUP_MAX_FAILS']='%CASE_MAX_FAILS%' } else { Remove-Item Env:KIMODO_WATCHDOG_STARTUP_MAX_FAILS -ErrorAction SilentlyContinue };" ^
  "if('%CASE_CONNECT_MS%' -ne ''){ $envMap['KIMODO_WATCHDOG_CONNECT_TIMEOUT_MS']='%CASE_CONNECT_MS%' } else { Remove-Item Env:KIMODO_WATCHDOG_CONNECT_TIMEOUT_MS -ErrorAction SilentlyContinue };" ^
  "if('%CASE_RUNTIME_INTERVAL%' -ne ''){ $envMap['KIMODO_WATCHDOG_RUNTIME_INTERVAL_SEC']='%CASE_RUNTIME_INTERVAL%' } else { Remove-Item Env:KIMODO_WATCHDOG_RUNTIME_INTERVAL_SEC -ErrorAction SilentlyContinue };" ^
  "if('%CASE_IDLE_NOLOG_MAX%' -ne ''){ $envMap['KIMODO_WATCHDOG_IDLE_NOLOG_MAX']='%CASE_IDLE_NOLOG_MAX%' } else { Remove-Item Env:KIMODO_WATCHDOG_IDLE_NOLOG_MAX -ErrorAction SilentlyContinue };" ^
  "$old=@{}; foreach($k in $envMap.Keys){ $old[$k]=[Environment]::GetEnvironmentVariable($k,'Process'); [Environment]::SetEnvironmentVariable($k,$envMap[$k],'Process') };" ^
  "try { $p=Start-Process -FilePath 'cmd.exe' -ArgumentList $argList -WorkingDirectory $root -RedirectStandardOutput $consoleLog -PassThru; Set-Content -LiteralPath $pidFile -Value $p.Id -Encoding ASCII } finally { foreach($k in $envMap.Keys){ [Environment]::SetEnvironmentVariable($k,$old[$k],'Process') } }"
if errorlevel 1 (
  echo [CASE:%CASE_NAME%] [ERROR] failed to start run_server
  set /a FAIL_COUNT+=1
  exit /b 0
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
ping 127.0.0.1 -n 2 >nul
set /a WAIT_SEC+=1
if !WAIT_SEC! geq 120 (
  echo [CASE:%CASE_NAME%] [ERROR] timeout waiting serverport
  call :kill_case_pid "%CASE_PID_FILE%"
  set /a FAIL_COUNT+=1
  exit /b 0
)
goto wait_port

:got_port
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue'; $h='%HOST%'; $p=[int]%PORT%; $c=$null; try { $c=New-Object Net.Sockets.TcpClient($h,$p); $s=$c.GetStream(); $w=New-Object IO.StreamWriter($s); $w.AutoFlush=$true; $w.WriteLine('{""cmd"":""quit""}'); $w.Close(); $s.Close() } finally { if($c){$c.Close()} }" >nul 2>nul

call :wait_case_exit "%CASE_PID_FILE%" 90

set "EXP_STARTUP_INTERVAL=%CASE_STARTUP_INTERVAL%"
if not defined EXP_STARTUP_INTERVAL set "EXP_STARTUP_INTERVAL=1"
set "EXP_STARTUP_MAX_FAILS=%CASE_MAX_FAILS%"
if not defined EXP_STARTUP_MAX_FAILS set "EXP_STARTUP_MAX_FAILS=30"
set "EXP_CONNECT_MS=%CASE_CONNECT_MS%"
if not defined EXP_CONNECT_MS set "EXP_CONNECT_MS=800"
set "EXP_RUNTIME_INTERVAL=%CASE_RUNTIME_INTERVAL%"
if not defined EXP_RUNTIME_INTERVAL set "EXP_RUNTIME_INTERVAL=1"
set "EXP_IDLE_NOLOG_MAX=%CASE_IDLE_NOLOG_MAX%"
if not defined EXP_IDLE_NOLOG_MAX set "EXP_IDLE_NOLOG_MAX=300"

set "EXPECT_A=startup_interval=%EXP_STARTUP_INTERVAL%s"
set "EXPECT_B=startup_max_fails=%EXP_STARTUP_MAX_FAILS%"
set "EXPECT_C=connect_timeout=%EXP_CONNECT_MS%ms"
set "EXPECT_D=runtime_interval=%EXP_RUNTIME_INTERVAL%s"
set "EXPECT_E=idle_nolog_max=%EXP_IDLE_NOLOG_MAX%"

findstr /C:"%EXPECT_A%" "%CASE_CONSOLE_LOG%" >nul || goto case_failed
findstr /C:"%EXPECT_B%" "%CASE_CONSOLE_LOG%" >nul || goto case_failed
findstr /C:"%EXPECT_C%" "%CASE_CONSOLE_LOG%" >nul || goto case_failed
findstr /C:"%EXPECT_D%" "%CASE_CONSOLE_LOG%" >nul || goto case_failed
findstr /C:"%EXPECT_E%" "%CASE_CONSOLE_LOG%" >nul || goto case_failed

echo [CASE:%CASE_NAME%] [PASS]
exit /b 0

:case_failed
echo [CASE:%CASE_NAME%] [FAIL] expected watchdog line not found
echo [CASE:%CASE_NAME%] expected: %EXPECT_A%
echo [CASE:%CASE_NAME%] expected: %EXPECT_B%
echo [CASE:%CASE_NAME%] expected: %EXPECT_C%
echo [CASE:%CASE_NAME%] expected: %EXPECT_D%
echo [CASE:%CASE_NAME%] expected: %EXPECT_E%
if exist "%CASE_CONSOLE_LOG%" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%CASE_CONSOLE_LOG%' -Tail 80"
)
call :kill_case_pid "%CASE_PID_FILE%"
set /a FAIL_COUNT+=1
exit /b 0

:wait_case_exit
set "WAIT_PID_FILE=%~1"
set /a WAIT_MAX=%~2
if not exist "%WAIT_PID_FILE%" exit /b 0
set "WPID="
for /f "usebackq delims=" %%A in ("%WAIT_PID_FILE%") do (
  if not defined WPID set "WPID=%%A"
)
if not defined WPID exit /b 0
set /a WAIT_CUR=0
:wait_case_loop
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$pidValue='%WPID%'; if($pidValue -notmatch '^\d+$'){ exit 0 }; $p=Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue; if($null -eq $p){ exit 0 } else { exit 1 }" >nul 2>nul
if not errorlevel 1 exit /b 0
ping 127.0.0.1 -n 2 >nul
set /a WAIT_CUR+=1
if !WAIT_CUR! geq !WAIT_MAX! (
  call :kill_case_pid "%WAIT_PID_FILE%"
  exit /b 0
)
goto wait_case_loop

:kill_case_pid
set "KILL_PID_FILE=%~1"
if not exist "%KILL_PID_FILE%" exit /b 0
set "KPID="
for /f "usebackq delims=" %%A in ("%KILL_PID_FILE%") do (
  if not defined KPID set "KPID=%%A"
)
if defined KPID (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='SilentlyContinue'; $pidValue='%KPID%'; if($pidValue -match '^\d+$'){ Stop-Process -Id ([int]$pidValue) -Force -ErrorAction SilentlyContinue }" >nul 2>nul
)
exit /b 0

:archive_file
set "ARCHIVE_TARGET=%~1"
if not exist "%ARCHIVE_TARGET%" exit /b 0
set "TS=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "TS=%TS: =0%"
set "BASE=%~nx1"
set "DEST=%ARCHIVE_DIR%\%BASE%.%TS%.%RANDOM%"
move "%ARCHIVE_TARGET%" "%DEST%" >nul 2>nul
exit /b 0
