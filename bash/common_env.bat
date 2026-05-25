@echo off

if /I "%~1"==":resolve_venv_python" (
  shift
  goto resolve_venv_python
)
if /I "%~1"==":archive_file" (
  shift
  goto archive_file
)
if /I "%~1"==":is_kimodo_bridge_pid" (
  shift
  goto is_kimodo_bridge_pid
)
if /I "%~1"==":kill_pid_if_kimodo_bridge" (
  shift
  goto kill_pid_if_kimodo_bridge
)
if /I "%~1"==":eof" exit /b 0
if "%~1"=="" exit /b 0

:resolve_venv_python
set "VENV_INPUT=%~1"
if not defined VENV_INPUT (
  echo [ERROR] --venv requires a path.
  exit /b 1
)
for %%I in ("%VENV_INPUT%") do set "VENV_INPUT_ABS=%%~fI"
set "VENV_CAND=%VENV_INPUT_ABS%"
if /I "%VENV_CAND:~-10%"=="python.exe" goto common_venv_resolved
if /I "%VENV_CAND:~-8%"=="\Scripts" (
  set "VENV_CAND=%VENV_CAND%\python.exe"
) else (
  set "VENV_CAND=%VENV_CAND%\Scripts\python.exe"
)
:common_venv_resolved
if not exist "%VENV_CAND%" (
  echo [ERROR] Invalid --venv path, python not found: %VENV_CAND%
  exit /b 1
)
for %%I in ("%VENV_CAND%") do set "VENV_PY=%%~fI"
exit /b 0

:archive_file
set "ARCHIVE_TARGET=%~1"
set "ARCHIVE_RECYCLE_DIR=%~2"
if not exist "%ARCHIVE_TARGET%" exit /b 0
if not defined ARCHIVE_RECYCLE_DIR (
  if defined ROOT_DIR (
    set "ARCHIVE_RECYCLE_DIR=%ROOT_DIR%\archive\recycle"
  ) else (
    set "ARCHIVE_RECYCLE_DIR=%~dp0..\archive\recycle"
  )
)
if not exist "%ARCHIVE_RECYCLE_DIR%" mkdir "%ARCHIVE_RECYCLE_DIR%" >nul 2>nul
set "TS=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "TS=%TS: =0%"
set "BASE=%~nx1"
set "DEST=%ARCHIVE_RECYCLE_DIR%\%BASE%.%TS%.%RANDOM%"
move "%ARCHIVE_TARGET%" "%DEST%" >nul 2>nul
exit /b 0

:is_kimodo_bridge_pid
set "CHECK_PID=%~1"
if not defined CHECK_PID exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue'; $pidVal=[int]%CHECK_PID%; $p=Get-CimInstance Win32_Process -Filter ('ProcessId=' + $pidVal); if(-not $p){ exit 1 }; $name=[string]$p.Name; $cmd=[string]$p.CommandLine; if($name -notmatch '^(python|pythonw)\.exe$'){ exit 2 }; if(($cmd -match 'kimodo\.bridge\.bridge_server') -and ($cmd -match '--kimodo-root')){ exit 0 } else { exit 3 }" >nul 2>nul
if errorlevel 1 exit /b 1
exit /b 0

:kill_pid_if_kimodo_bridge
set "KILL_PID_VALUE=%~1"
if not defined KILL_PID_VALUE exit /b 1
call "%~f0" :is_kimodo_bridge_pid "%KILL_PID_VALUE%"
if errorlevel 1 exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Stop-Process -Id %KILL_PID_VALUE% -Force -ErrorAction SilentlyContinue" >nul 2>nul
exit /b 0
