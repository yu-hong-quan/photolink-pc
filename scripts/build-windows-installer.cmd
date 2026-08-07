@echo off
REM ?? / ????build-windows-installer.cmd local
set ENV=%1
if "%ENV%"=="" set ENV=prod
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-windows-installer.ps1" -EnvName %ENV%
