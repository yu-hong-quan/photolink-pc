# 运行 Windows 调试
# 用法：.\scripts\run-windows.ps1 -Env local

param(
  [ValidateSet('local', 'test', 'prod')]
  [string]$EnvName = 'local'
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
. "$PSScriptRoot\_env.ps1" -EnvName $EnvName

flutter pub get
flutter run -d windows @PhotoLinkDefines
