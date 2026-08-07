# PhotoLink 打包环境说明（PC）
#
# 通过 --dart-define=FLAVOR=local|test|prod 切换：
#   local  相册 53337 / 配对 53338
#   test   相册 53327 / 配对 53328
#   prod   相册 53317 / 配对 53318（默认）
#
# 须与手机端同一 FLAVOR。

param(
  [ValidateSet('local', 'test', 'prod')]
  [string]$EnvName = 'prod'
)

$script:PhotoLinkDefines = @(
  "--dart-define=FLAVOR=$EnvName"
)

Write-Host "PhotoLink PC FLAVOR=$EnvName" -ForegroundColor Cyan
Write-Host ("Defines: " + ($PhotoLinkDefines -join ' '))
