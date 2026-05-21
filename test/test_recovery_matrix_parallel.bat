@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "CASES_DIR=%SCRIPT_DIR%\cases"
set "RESULT_DIR=%SCRIPT_DIR%\results"
set "LOG_DIR=%SCRIPT_DIR%\log"
set "MATRIX_LOG=%LOG_DIR%\recovery_matrix_parallel.log"
set "PASS_COUNT=0"
set "FAIL_COUNT=0"
set "FAILED="
set "ONLY_SCENARIO=%KIMODO_MATRIX_ONLY%"
if defined ONLY_SCENARIO for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$v=$env:KIMODO_MATRIX_ONLY; if($null -eq $v){''} else {$v.Trim()}"`) do set "ONLY_SCENARIO=%%A"

if not exist "%CASES_DIR%" (
  echo [ERROR] cases dir missing: %CASES_DIR%
  exit /b 1
)
if not exist "%RESULT_DIR%" mkdir "%RESULT_DIR%" >nul 2>nul
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul

> "%MATRIX_LOG%" echo [MATRIX] start %DATE% %TIME%
call :log "[MATRIX] mode=parallel timeout_sec=900 visible_windows=on"
if defined ONLY_SCENARIO call :log "[MATRIX] only_scenario=%ONLY_SCENARIO%"

set "CASE_LIST=case_download_interrupt_once case_download_network_bad_once case_download_then_model_missing_once case_setup_interrupt_once case_setup_network_bad_once case_setup_not_started case_highvram_soma case_model_variant_g1_rp case_model_variant_smplx_rp case_model_variant_soma_seed case_local_tools_uv_git"

for %%C in (%CASE_LIST%) do (
  if defined ONLY_SCENARIO (
    if /I not "%ONLY_SCENARIO%"=="%%C" (
      rem skip
    ) else (
      call :launch_case "%%C"
    )
  ) else (
    call :launch_case "%%C"
  )
)

for %%C in (%CASE_LIST%) do (
  if defined ONLY_SCENARIO (
    if /I not "%ONLY_SCENARIO%"=="%%C" (
      rem skip
    ) else (
      call :wait_case "%%C"
    )
  ) else (
    call :wait_case "%%C"
  )
)

call :log "[SUMMARY] pass=%PASS_COUNT% fail=%FAIL_COUNT%"
if defined FAILED call :log "[SUMMARY] failed=%FAILED%"
if %FAIL_COUNT% GTR 0 exit /b 1
exit /b 0

:launch_case
set "CASE_NAME=%~1"
set "CASE_BAT=%CASES_DIR%\%CASE_NAME%.bat"
set "RESULT_FILE=%RESULT_DIR%\%CASE_NAME%.result"
set "PID_FILE=%RESULT_DIR%\%CASE_NAME%.pid"
if not exist "%CASE_BAT%" (
  call :log "[ERROR] missing case bat: %CASE_BAT%"
  > "%RESULT_FILE%" (
    echo CASE_NAME=%CASE_NAME%
    echo STATUS=FAIL
    echo DETAIL=case_script_missing
  )
  exit /b 0
)
if exist "%RESULT_FILE%" move "%RESULT_FILE%" "%RESULT_FILE%.old.%RANDOM%" >nul 2>nul
if exist "%PID_FILE%" move "%PID_FILE%" "%PID_FILE%.old.%RANDOM%" >nul 2>nul
set "PS_CMD=$ErrorActionPreference='Stop'; $case='%CASE_BAT%'; $res='%RESULT_FILE%'; $pidf='%PID_FILE%'; $p=Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d','/c',$case,$res) -WindowStyle Normal -PassThru; Set-Content -LiteralPath $pidf -Value $p.Id -Encoding ASCII"
powershell -NoProfile -ExecutionPolicy Bypass -Command "%PS_CMD%"
if errorlevel 1 (
  call :log "[ERROR] launch failed: %CASE_NAME%"
  > "%RESULT_FILE%" (
    echo CASE_NAME=%CASE_NAME%
    echo STATUS=FAIL
    echo DETAIL=launch_failed
  )
) else (
  call :log "[CASE] %CASE_NAME% launched"
)
exit /b 0

:wait_case
set "CASE_NAME=%~1"
set "RESULT_FILE=%RESULT_DIR%\%CASE_NAME%.result"
set "PID_FILE=%RESULT_DIR%\%CASE_NAME%.pid"
call :wait_for_pid_or_result "%PID_FILE%" "%RESULT_FILE%" 10
if exist "%PID_FILE%" (
  set "CPID="
  for /f "usebackq delims=" %%P in ("%PID_FILE%") do if not defined CPID set "CPID=%%P"
)
if defined CPID (
  call :wait_pid_exit "%CPID%" 900
  set "WRC=%ERRORLEVEL%"
  if "%WRC%"=="124" (
    > "%RESULT_FILE%" (
      echo CASE_NAME=%CASE_NAME%
      echo STATUS=FAIL
      echo DETAIL=timeout_900s
    )
  )
)
if not exist "%RESULT_FILE%" call :wait_for_result "%RESULT_FILE%" 5

set "STATUS=FAIL"
set "DETAIL=result_missing"
if exist "%RESULT_FILE%" (
  for /f "usebackq tokens=1,* delims==" %%A in ("%RESULT_FILE%") do (
    if /I "%%A"=="STATUS" set "STATUS=%%B"
    if /I "%%A"=="DETAIL" set "DETAIL=%%B"
  )
)
if /I "%STATUS%"=="PASS" (
  set /a PASS_COUNT+=1
  call :log "[CASE] %CASE_NAME% PASS"
) else (
  set /a FAIL_COUNT+=1
  if defined FAILED (
    set "FAILED=%FAILED%,%CASE_NAME%"
  ) else (
    set "FAILED=%CASE_NAME%"
  )
  call :log "[CASE] %CASE_NAME% FAIL: %DETAIL%"
)
exit /b 0

:wait_for_pid_or_result
set "W_PID_FILE=%~1"
set "W_RESULT_FILE=%~2"
set "W_TIMEOUT=%~3"
if not defined W_TIMEOUT set "W_TIMEOUT=5"
set /a W_ELAPSED=0
:wait_pid_or_result_loop
if exist "%W_PID_FILE%" exit /b 0
if exist "%W_RESULT_FILE%" exit /b 0
if "%W_ELAPSED%" geq "%W_TIMEOUT%" exit /b 0
ping 127.0.0.1 -n 2 >nul
set /a W_ELAPSED+=1
goto wait_pid_or_result_loop

:wait_for_result
set "W_RESULT_FILE=%~1"
set "W_TIMEOUT=%~2"
if not defined W_TIMEOUT set "W_TIMEOUT=5"
set /a W_ELAPSED=0
:wait_result_loop
if exist "%W_RESULT_FILE%" exit /b 0
if "%W_ELAPSED%" geq "%W_TIMEOUT%" exit /b 0
ping 127.0.0.1 -n 2 >nul
set /a W_ELAPSED+=1
goto wait_result_loop

:wait_pid_exit
set "WPID=%~1"
set "WTIMEOUT=%~2"
if not defined WTIMEOUT set "WTIMEOUT=900"
if not defined WPID exit /b 0
echo %WPID%| findstr /R "^[0-9][0-9]*$" >nul
if errorlevel 1 exit /b 0
set /a WELAPSED=0
:wait_pid_loop
tasklist /FI "PID eq %WPID%" | findstr /R /C:"[ ]%WPID%[ ]" >nul
if errorlevel 1 exit /b 0
if %WELAPSED% GEQ %WTIMEOUT% (
  taskkill /PID %WPID% /T /F >nul 2>nul
  exit /b 124
)
ping 127.0.0.1 -n 2 >nul
set /a WELAPSED+=1
goto wait_pid_loop

:log
echo %~1
>> "%MATRIX_LOG%" echo %~1
exit /b 0
