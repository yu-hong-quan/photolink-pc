#!/usr/bin/env bash
# 打包 macOS .app（需在 Mac 执行）
# 用法：./scripts/build-macos.sh prod
# 产物：build/macos/Build/Products/Release/PhotoLink.app（或 photolink_pc.app）
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

APP_DIR="build/macos/Build/Products/Release"
if [[ -d "$APP_DIR/PhotoLink.app" ]]; then
  echo "完成：$APP_DIR/PhotoLink.app"
elif [[ -d "$APP_DIR/photolink_pc.app" ]]; then
  echo "完成：$APP_DIR/photolink_pc.app"
else
  echo "未找到 .app 产物，请检查 $APP_DIR"
  ls -la "$APP_DIR" || true
  exit 1
fi
