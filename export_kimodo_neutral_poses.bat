@echo off
setlocal EnableExtensions

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"

set "VENV_PY=%ROOT_DIR%\.venv\Scripts\python.exe"
set "EMBED_PY=%ROOT_DIR%\python312\python.exe"
set "PY_EXE="

if exist "%VENV_PY%" set "PY_EXE=%VENV_PY%"
if not defined PY_EXE if exist "%EMBED_PY%" set "PY_EXE=%EMBED_PY%"

if not defined PY_EXE (
  echo [ERROR] Python not found.
  echo [ERROR] Checked:
  echo [ERROR]   %VENV_PY%
  echo [ERROR]   %EMBED_PY%
  exit /b 1
)

set "ASSETS_ROOT=%ROOT_DIR%\kimodo\kimodo\assets\skeletons"
set "OUT_DIR=%ROOT_DIR%\neutral_pose_exports"
set "SCRIPT=%ROOT_DIR%\tools\export_kimodo_neutral_poses.py"

if not exist "%SCRIPT%" (
  echo [ERROR] Export script not found: %SCRIPT%
  exit /b 1
)

if not exist "%ASSETS_ROOT%" (
  echo [ERROR] Skeleton assets directory not found: %ASSETS_ROOT%
  exit /b 1
)

"%PY_EXE%" "%SCRIPT%" --assets-root "%ASSETS_ROOT%" --out-dir "%OUT_DIR%"
if errorlevel 1 (
  echo [ERROR] Neutral pose export failed.
  exit /b 1
)

echo [INFO] Export completed. Output directory: %OUT_DIR%
exit /b 0
