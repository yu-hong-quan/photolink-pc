@echo off
REM 双击 / 命令行：build-windows.cmd prod
set ENV=%1
if "%ENV%"=="" set ENV=prod
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-windows.ps1" -EnvName %ENV%
