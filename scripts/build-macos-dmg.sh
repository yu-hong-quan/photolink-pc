#!/usr/bin/env bash
# 打包 macOS DMG（需在 Mac 执行，可上传 GitHub Releases）
# 用法：
#   ./scripts/build-macos-dmg.sh prod
#   ./scripts/build-macos-dmg.sh prod --skip-build   # 仅用已有 .app 重打 DMG
# 产物：
#   build/macos/Build/Products/Release/PhotoLink.app
#   releases/PhotoLink-{version}-{env}-macos.dmg
#
# 说明：当前为未公证分发包。他人首次打开可能被 Gatekeeper 拦截，
# 需右键「打开」或在「隐私与安全性」中允许。

set -euo pipefail

ENV_NAME="${1:-prod}"
SKIP_BUILD=0
if [[ "${2:-}" == "--skip-build" ]]; then
  SKIP_BUILD=1
fi

case "$ENV_NAME" in
  local|test|prod) ;;
  *)
    echo "用法: $0 local|test|prod [--skip-build]"
    exit 1
    ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(
  awk '
    /^[[:space:]]*version:[[:space:]]*/ {
      v = $2
      sub(/\+.*/, "", v)
      print v
      exit
    }
  ' pubspec.yaml
)"
if [[ -z "$VERSION" ]]; then
  echo "无法从 pubspec.yaml 解析 version"
  exit 1
fi

APP_DIR="build/macos/Build/Products/Release"
resolve_app() {
  if [[ -d "$APP_DIR/PhotoLink.app" ]]; then
    echo "$APP_DIR/PhotoLink.app"
  elif [[ -d "$APP_DIR/photolink_pc.app" ]]; then
    echo "$APP_DIR/photolink_pc.app"
  else
    echo ""
  fi
}

DMG_NAME="PhotoLink-${VERSION}-${ENV_NAME}-macos.dmg"
RELEASES_DIR="$ROOT/releases"
STAGING="$ROOT/build/dmg-staging"
VOL_NAME="PhotoLink"

echo "PhotoLink macOS DMG FLAVOR=$ENV_NAME VERSION=$VERSION"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  ./scripts/build-macos.sh "$ENV_NAME"
else
  echo "跳过 flutter build（--skip-build）"
fi

APP_SRC="$(resolve_app)"
if [[ -z "$APP_SRC" ]]; then
  echo "缺少 .app 产物，请检查 $APP_DIR"
  ls -la "$APP_DIR" || true
  exit 1
fi

rm -rf "$STAGING"
mkdir -p "$STAGING" "$RELEASES_DIR"

# DMG 内使用友好名称 PhotoLink.app
ditto "$APP_SRC" "$STAGING/PhotoLink.app"
# 强制使用 AppIcon.icns，避免 Assets.car / Launchpad 缓存仍显示旧 Flutter 图标
INFO_PLIST="$STAGING/PhotoLink.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$INFO_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$INFO_PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$INFO_PLIST"
# 修改 Info.plist 后必须重新签名，否则沙盒初始化会直接崩溃（OSStatus -67030）
echo ">>> ad-hoc 重新签名..."
codesign --force --deep --sign - "$STAGING/PhotoLink.app"
codesign --verify --deep --strict "$STAGING/PhotoLink.app"
ln -s /Applications "$STAGING/Applications"

DMG_PATH="$RELEASES_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

echo ">>> 创建 DMG: $DMG_PATH"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGING"

echo "完成："
echo "  App : $APP_SRC"
echo "  DMG : $DMG_PATH"
echo ""
echo "分发提示（未公证）："
echo "  1. 下载 DMG → 将 PhotoLink.app 拖到「应用程序」"
echo "  2. 若提示无法验证开发者：右键 App → 打开 → 仍要打开"
echo "  3. 或：系统设置 → 隐私与安全性 → 仍要打开"
