@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
set "RESULT_FILE=%~1"
if not defined RESULT_FILE set "RESULT_FILE=%TEMP%\kimodo_case_local_tools_%RANDOM%%RANDOM%.txt"
set "ROOT_DIR=%SCRIPT_DIR%\..\.."
pushd "%ROOT_DIR%" >nul
call "%ROOT_DIR%\example\example_test_local_tools.bat"
set "RC=%ERRORLEVEL%"
popd >nul
> "%RESULT_FILE%" (
  echo CASE_NAME=local_tools_uv_git
  if "%RC%"=="0" (
    echo STATUS=PASS
    echo DETAIL=ok
  ) else (
    echo STATUS=FAIL
    echo DETAIL=local_tools_failed_rc_%RC%
  )
)
exit /b %RC%
