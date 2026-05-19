@echo off
setlocal EnableExtensions
cd /d "%~dp0"
call "%~dp0clonemodel.bat" -highvram %*
exit /b %ERRORLEVEL%
