# PhotoLink PC Windows 安装包（Inno Setup）
# 用法：.\scripts\build-windows-installer.ps1 -EnvName local
# 产物：dist\installer\PhotoLink-Setup-{version}-{env}.exe
# 说明：安装路径支持中文；需本机安装 Inno Setup 6。

param(
  [ValidateSet('local', 'test', 'prod')]
  [string]$EnvName = 'prod',
  # 仅编译已有 Release，跳过 flutter build（调试安装脚本时用）
  [switch]$SkipFlutterBuild
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
Set-Location $RepoRoot
. "$PSScriptRoot\_env.ps1" -EnvName $EnvName

function Get-PhotoLinkVersion {
  $pubspec = Join-Path $RepoRoot 'pubspec.yaml'
  $line = Get-Content -LiteralPath $pubspec -Encoding UTF8 |
    Where-Object { $_ -match '^\s*version\s*:\s*' } |
    Select-Object -First 1
  if (-not $line) {
    throw '无法从 pubspec.yaml 读取 version'
  }
  # 形如 1.1.0+2 -> 取 1.1.0
  if ($line -match 'version\s*:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
    return $Matches[1]
  }
  throw "version 格式无法解析: $line"
}

function Find-Iscc {
  $candidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
  )
  foreach ($p in $candidates) {
    if ($p -and (Test-Path -LiteralPath $p)) {
      return $p
    }
  }
  $cmd = Get-Command iscc -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) {
    return $cmd.Source
  }
  return $null
}

$version = Get-PhotoLinkVersion
$outputName = "PhotoLink-Setup-$version-$EnvName"
$releaseDir = Join-Path $RepoRoot 'build\windows\x64\runner\Release'
$issFile = Join-Path $RepoRoot 'installer\windows\photolink.iss'
$iscc = Find-Iscc

Write-Host "PhotoLink installer EnvName=$EnvName Version=$version" -ForegroundColor Cyan

if (-not $iscc) {
  Write-Host '未找到 Inno Setup 6 (ISCC.exe)。请先安装: https://jrsoftware.org/isinfo.php' -ForegroundColor Red
  exit 1
}
Write-Host "ISCC: $iscc"

if (-not $SkipFlutterBuild) {
  Write-Host '>>> flutter pub get' -ForegroundColor Green
  flutter pub get
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host ">>> flutter build windows --release ($EnvName)" -ForegroundColor Green
  flutter build windows --release @PhotoLinkDefines
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
  Write-Host '跳过 flutter build（-SkipFlutterBuild）' -ForegroundColor Yellow
}

$exePath = Join-Path $releaseDir 'photolink_pc.exe'
if (-not (Test-Path -LiteralPath $exePath)) {
  Write-Host "缺少 Release 产物: $exePath" -ForegroundColor Red
  exit 1
}

$outDir = Join-Path $RepoRoot 'dist\installer'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host ">>> ISCC compile ($outputName)" -ForegroundColor Green
& $iscc `
  "/DMyAppVersion=$version" `
  "/DMyAppFlavor=$EnvName" `
  "/DMyAppOutputName=$outputName" `
  $issFile
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$setup = Join-Path $outDir "$outputName.exe"
if (-not (Test-Path -LiteralPath $setup)) {
  Write-Host "未找到安装包产物: $setup" -ForegroundColor Red
  exit 1
}

Write-Host "完成: $setup" -ForegroundColor Green
Write-Host '安装向导支持自定义中文路径。'