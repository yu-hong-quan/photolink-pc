#!/usr/bin/env bash
# 打包 macOS .app（需在 Mac 执行）
# 用法：./scripts/build-macos.sh prod
# 产物：build/macos/Build/Products/Release/photolink_pc.app
# 若需可分发 DMG（上传 GitHub）：./scripts/build-macos-dmg.sh prod

set -euo pipefail
ENV_NAME="${1:-prod}"
case "$ENV_NAME" in
  local|test|prod) ;;
  *) echo "用法: $0 local|test|prod"; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "PhotoLink macOS FLAVOR=$ENV_NAME"
flutter pub get
flutter build macos --release --dart-define="FLAVOR=$ENV_NAME"

echo "完成：build/macos/Build/Products/Release/photolink_pc.app"
