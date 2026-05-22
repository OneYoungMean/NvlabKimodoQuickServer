@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "SOURCE_ROOT=%SCRIPT_DIR%\.."
for %%I in ("%SOURCE_ROOT%") do set "SOURCE_NAME=%%~nxI"
set "TEST_ROOT=C:\nvlab\test"
for /f %%I in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-Date).ToString('yyyyMMdd_HHmmss_fff')"') do set "TS=%%I"
set "MATRIX_ROOT=%TEST_ROOT%\%SOURCE_NAME%_%TS%_recovery_matrix"
set "MATRIX_LOG=%MATRIX_ROOT%\log\recovery_matrix.log"
set "PASS_COUNT=0"
set "FAIL_COUNT=0"
set "SCENARIO_FAIL_LIST="
set "SHARED_MODELS_ROOT=C:\nvlab\models"
set "ONLY_SCENARIO=%KIMODO_MATRIX_ONLY%"
if defined ONLY_SCENARIO for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$v=$env:KIMODO_MATRIX_ONLY; if($null -eq $v){''} else {$v.Trim()}"`) do set "ONLY_SCENARIO=%%A"

if not exist "%SOURCE_ROOT%\run_server.bat" (
  echo [ERROR] Invalid source root: %SOURCE_ROOT%
  exit /b 1
)

if not exist "%TEST_ROOT%" mkdir "%TEST_ROOT%" >nul 2>nul
if not exist "%MATRIX_ROOT%" mkdir "%MATRIX_ROOT%" >nul 2>nul
if not exist "%MATRIX_ROOT%\log" mkdir "%MATRIX_ROOT%\log" >nul 2>nul

call :log "[MATRIX] source=%SOURCE_ROOT%"
call :log "[MATRIX] root=%MATRIX_ROOT%"
call :log "[MATRIX] default_test_output=file"
call :log "[MATRIX] shared_models_root=%SHARED_MODELS_ROOT%"
if defined ONLY_SCENARIO call :log "[MATRIX] only_scenario=%ONLY_SCENARIO%"

call :dispatch_standard "download_interrupt_once" "KIMODO_TEST_INJECT_DOWNLOAD_ABORT_ONCE=1"
call :dispatch_standard "download_network_bad_once" "KIMODO_TEST_INJECT_DOWNLOAD_NET_BAD_ONCE=1"
call :dispatch_standard "download_then_model_missing_once" "KIMODO_TEST_INJECT_MODEL_MISSING_AFTER_DOWNLOAD_ONCE=1"
call :dispatch_standard "setup_interrupt_once" "KIMODO_TEST_INJECT_SETUP_ABORT_ONCE=1"
call :dispatch_standard "setup_network_bad_once" "KIMODO_TEST_INJECT_SETUP_NET_BAD_ONCE=1"
call :dispatch_standard "setup_not_started" "KIMODO_TEST_FORCE_SETUP_NOT_STARTED=1"
call :dispatch_long_path
call :dispatch_model_variant "highvram_soma" "Kimodo-SOMA-RP-v1" "1" "1"
call :dispatch_model_variant "model_variant_g1_rp" "Kimodo-G1-RP-v1" "0" "0"
call :dispatch_model_variant "model_variant_smplx_rp" "Kimodo-SMPLX-RP-v1" "0" "0"
call :dispatch_model_variant "model_variant_soma_seed" "Kimodo-SOMA-SEED-v1" "0" "0"
call :dispatch_interrupt "interrupt_setup_cleanup" "setup"
call :dispatch_interrupt "interrupt_run_cleanup" "run"
call :dispatch_interrupt "interrupt_test_cleanup" "test"

call :log "[SUMMARY] pass=%PASS_COUNT% fail=%FAIL_COUNT%"
if not "%SCENARIO_FAIL_LIST%"=="" call :log "[SUMMARY] failed_scenarios=%SCENARIO_FAIL_LIST%"
if %FAIL_COUNT% GTR 0 exit /b 1
exit /b 0

:dispatch_standard
set "D_SCN=%~1"
if defined ONLY_SCENARIO if /I not "%ONLY_SCENARIO%"=="%D_SCN%" exit /b 0
call :run_standard_scenario "%~1" "%~2"
exit /b 0

:dispatch_long_path
set "D_SCN=path_too_long_then_normal_path_recovery"
if defined ONLY_SCENARIO if /I not "%ONLY_SCENARIO%"=="%D_SCN%" exit /b 0
call :run_long_path_recovery
exit /b 0

:dispatch_model_variant
set "D_SCN=%~1"
if defined ONLY_SCENARIO if /I not "%ONLY_SCENARIO%"=="%D_SCN%" exit /b 0
call :run_model_variant_case "%~1" "%~2" "%~3" "%~4"
exit /b 0

:dispatch_interrupt
set "D_SCN=%~1"
if defined ONLY_SCENARIO if /I not "%ONLY_SCENARIO%"=="%D_SCN%" exit /b 0
call :run_interrupt_cleanup_case "%~1" "%~2"
exit /b 0

:run_standard_scenario
set "SCENARIO=%~1"
set "INJECT_PAIR=%~2"
set "CASE_ROOT=%MATRIX_ROOT%\%SCENARIO%"
set "RUN_ROOT=%CASE_ROOT%\run"

call :log "[CASE] %SCENARIO% start"

call :prepare_case_copy "%RUN_ROOT%"
if errorlevel 1 (
  call :case_fail "%SCENARIO%" "prepare run failed"
  exit /b 0
)

call :set_injection_env "%INJECT_PAIR%" "%SCENARIO%"
if /I "%SCENARIO%"=="setup_not_started" call :force_setup_not_started "%RUN_ROOT%"
call :set_shared_models_policy "%SCENARIO%"

call :run_tpose_once "%RUN_ROOT%" "%SCENARIO%" "run1"
set "RC1=%ERRORLEVEL%"
call :clear_injection_env "%INJECT_PAIR%"
if not "%RC1%"=="0" (
  call :log "[CASE] %SCENARIO% run1 expected failure rc=%RC1%"
  call :log_tail "%RUN_ROOT%\log\example_run_server_tpose.log" 40
) else (
  call :log "[CASE] %SCENARIO% run1 unexpected success (allowed, continue)"
)

call :run_tpose_once "%RUN_ROOT%" "%SCENARIO%" "run2"
set "RC2=%ERRORLEVEL%"
if "%RC2%"=="0" (
  call :case_pass "%SCENARIO%"
  exit /b 0
)

call :case_fail "%SCENARIO%" "run2 failed rc=%RC2%"
call :log_tail "%RUN_ROOT%\log\example_run_server_tpose.log" 80
call :log_tail "%RUN_ROOT%\log\example_run_server_tpose_client.log" 80
call :log_tail "%RUN_ROOT%\log\setup.log" 80
call :log_tail "%RUN_ROOT%\log\download_model.log" 80
exit /b 0

:run_long_path_recovery
set "SCENARIO=path_too_long_then_normal_path_recovery"
set "CASE_ROOT=%MATRIX_ROOT%\%SCENARIO%"
set "LONG_SEG=segment0123456789segment0123456789segment0123456789"
set "LONG_ROOT=%CASE_ROOT%\long\%LONG_SEG%\%LONG_SEG%\%LONG_SEG%\%LONG_SEG%\%LONG_SEG%\%LONG_SEG%"
set "RUN2_ROOT=%CASE_ROOT%\run"

call :log "[CASE] %SCENARIO% start"

call :prepare_case_copy "%LONG_ROOT%"
if errorlevel 1 (
  call :log "[CASE] %SCENARIO% long path copy failed (treated as expected first-run failure)"
) else (
  call :run_tpose_once "%LONG_ROOT%" "%SCENARIO%" "run1_long"
  set "LONG_RC=%ERRORLEVEL%"
  if not "%LONG_RC%"=="0" (
    call :log "[CASE] %SCENARIO% run1 expected/acceptable failure rc=%LONG_RC%"
    call :log_tail "%LONG_ROOT%\log\example_run_server_tpose.log" 40
  ) else (
    call :log "[CASE] %SCENARIO% run1 succeeded under long path (system supports long path)"
  )
)

call :prepare_case_copy "%RUN2_ROOT%"
if errorlevel 1 (
  call :case_fail "%SCENARIO%" "prepare run2 failed"
  exit /b 0
)
call :run_tpose_once "%RUN2_ROOT%" "%SCENARIO%" "run2"
set "RC2=%ERRORLEVEL%"
if "%RC2%"=="0" (
  call :case_pass "%SCENARIO%"
  exit /b 0
)

call :case_fail "%SCENARIO%" "run2 failed rc=%RC2%"
call :log_tail "%RUN2_ROOT%\log\example_run_server_tpose.log" 80
call :log_tail "%RUN2_ROOT%\log\example_run_server_tpose_client.log" 80
call :log_tail "%RUN2_ROOT%\log\setup.log" 80
call :log_tail "%RUN2_ROOT%\log\download_model.log" 80
exit /b 0

:run_model_variant_case
set "SCENARIO=%~1"
set "MODEL_NAME=%~2"
set "HIGHVRAM=%~3"
set "USE_SHARED=%~4"
if not defined USE_SHARED set "USE_SHARED=0"
set "CASE_ROOT=%MATRIX_ROOT%\%SCENARIO%"
set "RUN_ROOT=%CASE_ROOT%\run"
call :log "[CASE] %SCENARIO% start model=%MODEL_NAME% highvram=%HIGHVRAM% use_shared=%USE_SHARED%"
call :prepare_case_copy "%RUN_ROOT%"
if errorlevel 1 (
  call :case_fail "%SCENARIO%" "prepare run failed"
  exit /b 0
)
set "KIMODO_TEST_MODEL=%MODEL_NAME%"
set "KIMODO_TEST_HIGHVRAM=%HIGHVRAM%"
set "KIMODO_TEST_USE_SHARED_MODELS=%USE_SHARED%"
call :run_tpose_once "%RUN_ROOT%" "%SCENARIO%" "run1"
set "RC=%ERRORLEVEL%"
set "KIMODO_TEST_MODEL="
set "KIMODO_TEST_HIGHVRAM="
set "KIMODO_TEST_USE_SHARED_MODELS="
if "%RC%"=="0" (
  call :case_pass "%SCENARIO%"
  exit /b 0
)
call :case_fail "%SCENARIO%" "run failed rc=%RC%"
call :log_tail "%RUN_ROOT%\log\example_run_server_tpose.log" 80
call :log_tail "%RUN_ROOT%\log\example_run_server_tpose_client.log" 80
call :log_tail "%RUN_ROOT%\log\run_server.log" 80
call :log_tail "%RUN_ROOT%\log\download_model.log" 80
exit /b 0

:run_interrupt_cleanup_case
set "SCENARIO=%~1"
set "INT_TARGET=%~2"
set "CASE_ROOT=%MATRIX_ROOT%\%SCENARIO%"
set "RUN_ROOT=%CASE_ROOT%\run"
set "INT_SERVER_PID_FILE=%RUN_ROOT%\log\%SCENARIO%_server_pid.txt"
call :log "[CASE] %SCENARIO% start target=%INT_TARGET%"
call :prepare_case_copy "%RUN_ROOT%"
if errorlevel 1 (
  call :case_fail "%SCENARIO%" "prepare run failed"
  exit /b 0
)
call :set_shared_models_policy "%SCENARIO%"
call :interrupt_once "%RUN_ROOT%" "%SCENARIO%" "%INT_TARGET%" "%INT_SERVER_PID_FILE%"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  call :case_fail "%SCENARIO%" "interrupt phase failed rc=%RC%"
  exit /b 0
)
call :assert_no_residual_process "%RUN_ROOT%"
set "RC_CHECK=%ERRORLEVEL%"
if not "%RC_CHECK%"=="0" (
  call :case_fail "%SCENARIO%" "residual process found after interrupt"
  exit /b 0
)
call :archive_stale_setup_lock "%RUN_ROOT%"
call :run_tpose_once "%RUN_ROOT%" "%SCENARIO%" "run2_after_interrupt"
set "RC2=%ERRORLEVEL%"
if "%RC2%"=="0" (
  call :case_pass "%SCENARIO%"
  exit /b 0
)
call :case_fail "%SCENARIO%" "run2 failed rc=%RC2%"
call :log_tail "%RUN_ROOT%\log\example_run_server_tpose.log" 80
call :log_tail "%RUN_ROOT%\log\example_run_server_tpose_client.log" 80
call :log_tail "%RUN_ROOT%\log\run_server.log" 80
call :log_tail "%RUN_ROOT%\log\setup.log" 80
exit /b 0

:prepare_case_copy
set "DEST_ROOT=%~1"
if exist "%DEST_ROOT%" call :archive_path "%DEST_ROOT%"
for %%I in ("%DEST_ROOT%") do set "DEST_PARENT=%%~dpI"
if not exist "%DEST_PARENT%" mkdir "%DEST_PARENT%" >nul 2>nul
set /a COPY_ATTEMPT=0
:copy_retry
set /a COPY_ATTEMPT+=1
robocopy "%SOURCE_ROOT%" "%DEST_ROOT%" /E /R:1 /W:1 /NFL /NDL /NJH /NJS ^
  /XD "%SOURCE_ROOT%\.git" "%SOURCE_ROOT%\archive" "%SOURCE_ROOT%\log" ^
      "%SOURCE_ROOT%\models" "%SOURCE_ROOT%\run" "%SOURCE_ROOT%\obstacle" "%SOURCE_ROOT%\hf_cache" ^
      "%SOURCE_ROOT%\kimodo\.venv" "%SOURCE_ROOT%\kimodo\hf_cache" "%SOURCE_ROOT%\kimodo\outputs" ^
      "%SOURCE_ROOT%\kimodo\benchmark" "%SOURCE_ROOT%\kimodo\__pycache__" ^
  /XF recovery_matrix.log "*.pyc" ".setup.lock" "serverport" ".run_server_state" "bridge_server.log" >nul
set "RBC=%ERRORLEVEL%"
if %RBC% LSS 8 goto copy_ok
if %COPY_ATTEMPT% GEQ 3 (
  call :log "[ERROR] copy failed rc=%RBC% attempts=%COPY_ATTEMPT% src=%SOURCE_ROOT% dst=%DEST_ROOT%"
  exit /b 1
)
call :log "[WARN] copy retry %COPY_ATTEMPT% rc=%RBC% dst=%DEST_ROOT%"
ping 127.0.0.1 -n 3 >nul
goto copy_retry
:copy_ok
call :link_shared_venv "%DEST_ROOT%"
if errorlevel 1 exit /b 1
exit /b 0

:run_tpose_once
set "CASE_ROOT=%~1"
set "SCENARIO_NAME=%~2"
set "ROUND_TAG=%~3"
set "TEST_BAT=%CASE_ROOT%\example\example_run_server_tpose.bat"
if not exist "%TEST_BAT%" (
  call :log "[ERROR] missing test bat: %TEST_BAT%"
  exit /b 1
)
if exist "%CASE_ROOT%\.setup.complete" if not exist "%CASE_ROOT%\kimodo\.venv\Scripts\python.exe" (
  call :log "[WARN] setup sentinel exists but .venv missing, forcing setup rerun."
  call :archive_path "%CASE_ROOT%\.setup.complete"
)

set "KIMODO_TEST_OUTPUT=file"
set "KIMODO_TEST_SCENARIO_NAME=%SCENARIO_NAME%_%ROUND_TAG%"
set "KIMODO_TEST_WAIT_TIMEOUT_SEC=600"
set "KIMODO_SHARED_MODELS_ROOT=%SHARED_MODELS_ROOT%"
call :log "[RUN] %SCENARIO_NAME% %ROUND_TAG% start cwd=%CASE_ROOT%"
pushd "%CASE_ROOT%" >nul
call "%TEST_BAT%"
set "RUN_RC=%ERRORLEVEL%"
popd >nul
call :log "[RUN] %SCENARIO_NAME% %ROUND_TAG% rc=%RUN_RC%"
exit /b %RUN_RC%

:link_shared_venv
set "DST_ROOT=%~1"
set "DST_VENV=%DST_ROOT%\kimodo\.venv"
set "SRC_VENV=%SOURCE_ROOT%\kimodo\.venv"
if not exist "%SRC_VENV%\Scripts\python.exe" (
  call :log "[WARN] source venv missing: %SRC_VENV% (setup may rebuild in case root)"
  exit /b 0
)
if exist "%DST_VENV%" (
  call :archive_path "%DST_VENV%"
)
if not exist "%DST_ROOT%\kimodo" mkdir "%DST_ROOT%\kimodo" >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$dst='%DST_VENV%'; $src='%SRC_VENV%'; if(Test-Path -LiteralPath $dst){ exit 0 }; New-Item -ItemType Junction -Path $dst -Target $src | Out-Null; exit 0"
if errorlevel 1 (
  call :log "[ERROR] failed to link shared venv dst=%DST_VENV% src=%SRC_VENV%"
  exit /b 1
)
call :log "[COPY] linked venv %DST_VENV% -> %SRC_VENV%"
exit /b 0

:set_injection_env
set "%~1"
set "KIMODO_TEST_SCENARIO_NAME=%~2"
exit /b 0

:clear_injection_env
for /f "tokens=1 delims==" %%A in ("%~1") do set "%%A="
set "KIMODO_TEST_SCENARIO_NAME="
set "KIMODO_TEST_FORCE_SETUP_NOT_STARTED="
exit /b 0

:set_shared_models_policy
set "SCN=%~1"
set "KIMODO_TEST_USE_SHARED_MODELS=1"
if /I "%SCN%"=="download_interrupt_once" set "KIMODO_TEST_USE_SHARED_MODELS=0"
if /I "%SCN%"=="download_network_bad_once" set "KIMODO_TEST_USE_SHARED_MODELS=0"
if /I "%SCN%"=="download_then_model_missing_once" set "KIMODO_TEST_USE_SHARED_MODELS=0"
if /I "%SCN:~0,13%"=="model_variant" set "KIMODO_TEST_USE_SHARED_MODELS=0"
if /I "%SCN:~0,9%"=="interrupt" set "KIMODO_TEST_USE_SHARED_MODELS=1"
exit /b 0

:interrupt_once
set "CASE_ROOT=%~1"
set "SCENARIO_NAME=%~2"
set "INT_TARGET=%~3"
set "INT_PID_FILE=%~4"
set "TEST_BAT=%CASE_ROOT%\example\example_run_server_tpose.bat"
set "INT_LOG=%CASE_ROOT%\log\%SCENARIO_NAME%_interrupt.log"
if not exist "%TEST_BAT%" (
  call :log "[ERROR] missing test bat: %TEST_BAT%"
  exit /b 1
)
pushd "%CASE_ROOT%" >nul
if /I "%INT_TARGET%"=="setup" if exist ".setup.complete" call :archive_path "%CASE_ROOT%\.setup.complete"
if not exist "%CASE_ROOT%\log" mkdir "%CASE_ROOT%\log" >nul 2>nul
if exist "%INT_PID_FILE%" call :archive_path "%INT_PID_FILE%"
set "KIMODO_TEST_OUTPUT=file"
set "KIMODO_TEST_WAIT_TIMEOUT_SEC=600"
set "KIMODO_TEST_SCENARIO_NAME=%SCENARIO_NAME%_interrupt"
set "KIMODO_TEST_SERVER_PID_FILE=%INT_PID_FILE%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; " ^
  "$root='%CASE_ROOT%'; $target='%INT_TARGET%'; $exe=Join-Path $root 'example\\example_run_server_tpose.bat'; $pidFile='%INT_PID_FILE%'; " ^
  "$env:KIMODO_TEST_OUTPUT='file'; $env:KIMODO_TEST_WAIT_TIMEOUT_SEC='600'; $env:KIMODO_TEST_SCENARIO_NAME='%SCENARIO_NAME%_interrupt'; $env:KIMODO_TEST_SERVER_PID_FILE=$pidFile; " ^
  "$p=Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d','/c',$exe) -WorkingDirectory $root -WindowStyle Normal -PassThru; " ^
  "$deadline=(Get-Date).AddMinutes(8); " ^
  "while((Get-Date) -lt $deadline){ " ^
  "  $hit=$false; " ^
  "  if($target -eq 'setup'){ $hit = Test-Path (Join-Path $root '.setup.lock') } " ^
  "  elseif($target -eq 'run'){ $hit = Test-Path (Join-Path $root 'serverport') } " ^
  "  elseif($target -eq 'test'){ $cl=Join-Path $root 'log\\example_run_server_tpose_client.log'; if(Test-Path $cl){ $hit=(Get-Content -LiteralPath $cl -Tail 20 | Select-String -Pattern 'status|ready|loading|generate' -Quiet) } } " ^
  "  if($hit){ break }; Start-Sleep -Milliseconds 500 " ^
  "}; " ^
  "try{ $portFile=Join-Path $root 'serverport'; if(Test-Path $portFile){ $txt=(Get-Content -LiteralPath $portFile -TotalCount 1 -ErrorAction SilentlyContinue); if($txt -match '^(?<h>[^:]+):(?<p>\d+)$'){ try{ $h=$Matches.h; $po=[int]$Matches.p; $c=New-Object Net.Sockets.TcpClient($h,$po); $s=$c.GetStream(); $w=New-Object IO.StreamWriter($s); $w.AutoFlush=$true; $w.WriteLine('{\"\"cmd\"\":\"\"quit\"\"}'); $w.Close(); $s.Close(); $c.Close() } catch {} } } } catch {}; " ^
  "try{ if(Test-Path -LiteralPath $pidFile){ $sid=(Get-Content -LiteralPath $pidFile -TotalCount 1 -ErrorAction SilentlyContinue).Trim(); if($sid -match '^\d+$'){ taskkill /PID $sid /T /F | Out-Null } } } catch {}; " ^
  "try{ taskkill /PID $($p.Id) /T /F | Out-Null } catch {}; Start-Sleep -Seconds 2; " ^
  "try{ if(Test-Path -LiteralPath $pidFile){ $sid=(Get-Content -LiteralPath $pidFile -TotalCount 1 -ErrorAction SilentlyContinue).Trim(); if($sid -match '^\d+$'){ taskkill /PID $sid /T /F | Out-Null } } } catch {}; " ^
  "exit 0"
set "INT_RC=%ERRORLEVEL%"
popd >nul
set "KIMODO_TEST_SERVER_PID_FILE="
exit /b %INT_RC%

:assert_no_residual_process
set "CASE_ROOT=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=[Regex]::Escape('%CASE_ROOT%'); $self=$PID; $bad = Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $self -and $_.CommandLine -and $_.CommandLine -match $root -and $_.Name -in @('cmd.exe','python.exe','uv.exe','git.exe','git-lfs.exe') }; if($bad){ $bad | Select-Object Name,ProcessId,ParentProcessId,CommandLine | Out-String | Write-Host; exit 1 } else { exit 0 }"
if errorlevel 1 (
  call :log "[CHECK] residual processes exist for %CASE_ROOT%"
  exit /b 1
)
call :log "[CHECK] no residual process for %CASE_ROOT%"
exit /b 0

:force_setup_not_started
set "TARGET_ROOT=%~1"
if exist "%TARGET_ROOT%\.setup.complete" (
  call :archive_path "%TARGET_ROOT%\.setup.complete"
)
set "KIMODO_TEST_FORCE_SETUP_NOT_STARTED=1"
exit /b 0

:archive_stale_setup_lock
set "TARGET_ROOT=%~1"
set "SETUP_LOCK=%TARGET_ROOT%\.setup.lock"
if not exist "%SETUP_LOCK%" exit /b 0
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=[Regex]::Escape('%TARGET_ROOT%'); $busy=Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine -match $root -and ($_.CommandLine -match 'setup\\.bat' -or $_.CommandLine -match 'setup_buildenv_impl\\.bat') }; if($busy){ exit 1 } else { exit 0 }"
if errorlevel 1 (
  call :log "[LOCK] setup lock still active: %SETUP_LOCK%"
  exit /b 0
)
call :log "[LOCK] archiving stale setup lock: %SETUP_LOCK%"
call :archive_path "%SETUP_LOCK%"
exit /b 0

:case_pass
set /a PASS_COUNT+=1
call :log "[CASE] %~1 PASS"
exit /b 0

:case_fail
set /a FAIL_COUNT+=1
if defined SCENARIO_FAIL_LIST (
  set "SCENARIO_FAIL_LIST=%SCENARIO_FAIL_LIST%,%~1"
) else (
  set "SCENARIO_FAIL_LIST=%~1"
)
call :log "[CASE] %~1 FAIL: %~2"
exit /b 0

:log_tail
set "TAIL_FILE=%~1"
set "TAIL_N=%~2"
if not exist "%TAIL_FILE%" (
  call :log "[TAIL] missing: %TAIL_FILE%"
  exit /b 0
)
call :log "[TAIL] %TAIL_FILE% last %TAIL_N% lines"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%TAIL_FILE%'; $n=%TAIL_N%; if(Test-Path -LiteralPath $p){ Get-Content -LiteralPath $p -Tail $n | ForEach-Object { Write-Host ('[TAIL] ' + $_) } }"
exit /b 0

:archive_path
set "ARCHIVE_TARGET=%~1"
if not exist "%ARCHIVE_TARGET%" exit /b 0
set "RECYCLE_DIR=%MATRIX_ROOT%\archive\recycle"
if not exist "%RECYCLE_DIR%" mkdir "%RECYCLE_DIR%" >nul 2>nul
set "ATS=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "ATS=%ATS: =0%"
for %%I in ("%ARCHIVE_TARGET%") do set "ABASE=%%~nxI"
set "ADEST=%RECYCLE_DIR%\%ABASE%.%ATS%.%RANDOM%"
move "%ARCHIVE_TARGET%" "%ADEST%" >nul 2>nul
exit /b 0

:log
echo %~1
>> "%MATRIX_LOG%" echo %~1
exit /b 0


