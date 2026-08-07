# 打包 Windows 桌面版（不含 Setup 安装包）
# 用法：.\scripts\build-windows.ps1 -EnvName prod
# 产物：build\windows\x64\runner\Release\
# 安装包请用：.\scripts\build-windows-installer.ps1 -EnvName prod

param(
  [ValidateSet('local', 'test', 'prod')]
  [string]$EnvName = 'prod'
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
. "$PSScriptRoot\_env.ps1" -EnvName $EnvName

Write-Host ">>> flutter pub get" -ForegroundColor Green
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ">>> flutter build windows --release ($EnvName)" -ForegroundColor Green
flutter build windows --release @PhotoLinkDefines
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$out = "build\windows\x64\runner\Release"
Write-Host "完成: $out\photolink_pc.exe" -ForegroundColor Green
Write-Host "分发请拷贝整个 Release 目录（含同目录 DLL）。"
Write-Host "或执行 build-windows-installer.ps1 生成 Setup.exe。"