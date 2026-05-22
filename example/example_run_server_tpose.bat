@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%\.."
set "LOG_DIR=%ROOT_DIR%\log"

set "LAUNCHER=%ROOT_DIR%\run_server.bat"
set "MODEL=Kimodo-SOMA-RP-v1"
if defined KIMODO_TEST_MODEL set "MODEL=%KIMODO_TEST_MODEL%"
set "HIGHVRAM=%KIMODO_TEST_HIGHVRAM%"
if not defined HIGHVRAM set "HIGHVRAM=0"
set "USE_SHARED_MODELS=%KIMODO_TEST_USE_SHARED_MODELS%"
if not defined USE_SHARED_MODELS set "USE_SHARED_MODELS=0"
set "SHARED_MODELS_ROOT=%KIMODO_SHARED_MODELS_ROOT%"
if not defined SHARED_MODELS_ROOT set "SHARED_MODELS_ROOT=C:\nvlab\models"
set "TEST_MODELS_ROOT=%KIMODO_TEST_MODELS_ROOT%"
if not defined TEST_MODELS_ROOT set "TEST_MODELS_ROOT="
if /I "%USE_SHARED_MODELS%"=="1" (
  if defined TEST_MODELS_ROOT set "SHARED_MODELS_ROOT=%TEST_MODELS_ROOT%"
)
set "PORT_FILE=%ROOT_DIR%\serverport"
set "RUN_LOG=%LOG_DIR%\example_run_server_tpose.log"
set "CLIENT_LOG=%LOG_DIR%\example_run_server_tpose_client.log"
set "CLIENT_PS1=%SCRIPT_DIR%\example_run_server_tpose_client.ps1"
set "SETUP_LOCK=%ROOT_DIR%\.setup.lock"
set "SERVER_STARTED=0"
set "SERVER_PID_FILE=%TEMP%\kimodo_test_server_pid_%RANDOM%%RANDOM%.txt"
if defined KIMODO_TEST_SERVER_PID_FILE set "SERVER_PID_FILE=%KIMODO_TEST_SERVER_PID_FILE%"
set "RECYCLE_DIR=%ROOT_DIR%\archive\recycle"
set "RESOLVE_MODEL_ALIAS_BAT=%ROOT_DIR%\bash\resolve_model_alias.bat"
set "SERVER_WINDOW_STYLE=%KIMODO_TEST_SERVER_WINDOW_STYLE%"
if not defined SERVER_WINDOW_STYLE set "SERVER_WINDOW_STYLE=Normal"

set "OUTPUT_MODE=%KIMODO_TEST_OUTPUT%"
if not defined OUTPUT_MODE set "OUTPUT_MODE=console"
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
echo [TEST] HIGHVRAM=%HIGHVRAM%
echo [TEST] USE_SHARED_MODELS=%USE_SHARED_MODELS%
if defined TEST_MODELS_ROOT echo [TEST] TEST_MODELS_ROOT=%TEST_MODELS_ROOT%
echo [TEST] MODE=%OUTPUT_MODE%

if /I "%USE_SHARED_MODELS%"=="1" (
  call :stage_shared_models
  if errorlevel 1 exit /b 1
)

call :decide_wait_timeout
echo [TEST] WAIT_TIMEOUT_SEC=%WAIT_TIMEOUT_SEC%
echo [TEST] SERVER_LOG=%RUN_LOG%
echo [TEST] SETUP_LOG=%LOG_DIR%\setup.log
echo [TEST] DOWNLOAD_LOG=%LOG_DIR%\download_model.log
echo [TEST] SERVER_WINDOW_STYLE=%SERVER_WINDOW_STYLE%

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
call :check_server_process_alive
if errorlevel 1 (
  echo [ERROR] Background run_server process exited before serverport was ready.
  if exist "%RUN_LOG%" (
    echo [TEST] run_server log tail:
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%RUN_LOG%'; if(Test-Path -LiteralPath $p){Get-Content -LiteralPath $p -Tail 120}"
  )
  if exist "%LOG_DIR%\setup.log" (
    echo [TEST] setup log tail:
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%LOG_DIR%\setup.log'; if(Test-Path -LiteralPath $p){Get-Content -LiteralPath $p -Tail 80}"
  )
  if exist "%LOG_DIR%\download_model.log" (
    echo [TEST] download log tail:
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%LOG_DIR%\download_model.log'; if(Test-Path -LiteralPath $p){Get-Content -LiteralPath $p -Tail 80}"
  )
  exit /b 1
)

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
call :try_quit_if_running
call :wait_server_exit_or_kill
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
call :archive_file "%RUN_LOG%"
set "LAUNCH_PS=$ErrorActionPreference='Stop'; $launcher='%LAUNCHER%'; $wd='%ROOT_DIR%'; $model='%MODEL%'; $logPath='%RUN_LOG%'; $outputMode='%OUTPUT_MODE%'; if([string]::IsNullOrWhiteSpace($outputMode)){ $outputMode='console' }; if($outputMode -ieq 'file'){ $argList=@('/d','/c',$launcher,'--model',$model,'--output','file','--log',$logPath) } else { $argList=@('/d','/c',$launcher,'--model',$model,'--output','console') }; if('%HIGHVRAM%' -eq '1'){ $argList += '--highvram' }; $modelsRoot='%TEST_MODELS_ROOT%'; if(-not [string]::IsNullOrWhiteSpace($modelsRoot)){ $argList += @('--models-root',$modelsRoot) }; $winStyle='%SERVER_WINDOW_STYLE%'; if([string]::IsNullOrWhiteSpace($winStyle)){ $winStyle='Normal' }; $p=Start-Process -FilePath 'cmd.exe' -ArgumentList $argList -WorkingDirectory $wd -WindowStyle $winStyle -PassThru; Set-Content -LiteralPath '%SERVER_PID_FILE%' -Value $p.Id -Encoding ASCII"
call powershell -NoProfile -ExecutionPolicy Bypass -Command "%LAUNCH_PS%"
if errorlevel 1 (
  echo [ERROR] launch_server_background failed.
  exit /b 1
)
set "SERVER_STARTED=1"
exit /b 0

:check_server_process_alive
if not exist "%SERVER_PID_FILE%" exit /b 0
set "SPID="
for /f "usebackq delims=" %%A in ("%SERVER_PID_FILE%") do (
  if not defined SPID set "SPID=%%A"
)
if not defined SPID exit /b 0
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$pidValue='%SPID%'; if($pidValue -notmatch '^\d+$'){ exit 1 }; $p=Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue; if($null -eq $p){ exit 1 }; exit 0" >nul 2>nul
if errorlevel 1 exit /b 1
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

:wait_server_exit_or_kill
if not exist "%SERVER_PID_FILE%" exit /b 0
set "SPID="
for /f "usebackq delims=" %%A in ("%SERVER_PID_FILE%") do (
  if not defined SPID set "SPID=%%A"
)
if not defined SPID exit /b 0
set /a EXIT_WAIT=0
:wait_server_exit_loop
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$pidValue='%SPID%'; if($pidValue -notmatch '^\d+$'){ exit 0 }; $p=Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue; if($null -eq $p){ exit 0 } else { exit 1 }" >nul 2>nul
if not errorlevel 1 (
  call :archive_file "%SERVER_PID_FILE%"
  exit /b 0
)
call :sleep_1s_or_cancel
set /a EXIT_WAIT+=1
if !EXIT_WAIT! geq 20 (
  echo [WARN] Server did not exit after quit within 20s. Forcing stop.
  call :try_kill_server_pid
  exit /b 0
)
goto wait_server_exit_loop

:stage_shared_models
if not exist "%SHARED_MODELS_ROOT%" (
  echo [ERROR] Shared models root not found: %SHARED_MODELS_ROOT%
  exit /b 1
)
if not exist "%ROOT_DIR%\models" mkdir "%ROOT_DIR%\models" >nul 2>nul
if not exist "%RESOLVE_MODEL_ALIAS_BAT%" (
  echo [ERROR] Missing model alias resolver: %RESOLVE_MODEL_ALIAS_BAT%
  exit /b 1
)
call "%RESOLVE_MODEL_ALIAS_BAT%" "%MODEL%"
if errorlevel 1 exit /b 1
call :copy_model_dir "%SHARED_MODELS_ROOT%\%MODEL_DIR_NAME%" "%ROOT_DIR%\models\%MODEL_DIR_NAME%"
if errorlevel 1 exit /b 1
if /I "%HIGHVRAM%"=="1" (
  call :copy_model_dir "%SHARED_MODELS_ROOT%\Meta-Llama-3-8B-Instruct" "%ROOT_DIR%\models\Meta-Llama-3-8B-Instruct"
  if errorlevel 1 exit /b 1
  call :copy_model_dir "%SHARED_MODELS_ROOT%\LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised" "%ROOT_DIR%\models\LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised"
  if errorlevel 1 exit /b 1
) else (
  call :copy_model_dir "%SHARED_MODELS_ROOT%\KIMODO-Meta3_llm2vec_NF4" "%ROOT_DIR%\models\KIMODO-Meta3_llm2vec_NF4"
  if errorlevel 1 exit /b 1
)
echo [TEST] Shared models staged from %SHARED_MODELS_ROOT%.
exit /b 0

:copy_model_dir
set "SRC_DIR=%~1"
set "DST_DIR=%~2"
if not exist "%SRC_DIR%" (
  echo [ERROR] Shared model source missing: %SRC_DIR%
  exit /b 1
)
if not exist "%DST_DIR%" mkdir "%DST_DIR%" >nul 2>nul
robocopy "%SRC_DIR%" "%DST_DIR%" /E /R:1 /W:1 /NFL /NDL /NJH /NJS >nul
set "RBC=%ERRORLEVEL%"
if %RBC% GEQ 8 (
  echo [ERROR] Failed to stage model directory: %SRC_DIR%
  exit /b 1
)
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


