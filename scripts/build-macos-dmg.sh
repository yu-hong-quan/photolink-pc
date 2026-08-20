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

RES="$STAGING/PhotoLink.app/Contents/Resources"
INFO_PLIST="$STAGING/PhotoLink.app/Contents/Info.plist"
ICON_PNG="$ROOT/assets/icons/app_icon.png"

# 用源 PNG 现编一份已知正确的 AppIcon.icns，覆盖构建产物
# （避免 Xcode/actool 缓存导致 Dock/启动台仍用旧白边图标）
echo ">>> 重新生成 AppIcon.icns..."
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16     "$ICON_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32     "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$ICON_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64     "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$ICON_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256   "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$ICON_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512   "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$ICON_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"

# 同步刷新 Assets.car 中的 AppIcon，避免系统优先读到旧 car
echo ">>> 重新编译 Assets.car..."
ACTOOL_OUT="$ROOT/build/actool-out"
rm -rf "$ACTOOL_OUT"
mkdir -p "$ACTOOL_OUT"
xcrun actool "$ROOT/macos/Runner/Assets.xcassets" \
  --compile "$ACTOOL_OUT" \
  --platform macosx \
  --minimum-deployment-target 10.15 \
  --app-icon AppIcon \
  --output-partial-info-plist "$ACTOOL_OUT/partial.plist" >/dev/null
if [[ -f "$ACTOOL_OUT/Assets.car" ]]; then
  cp "$ACTOOL_OUT/Assets.car" "$RES/Assets.car"
fi
# icns 仍用我们 iconutil 产物（更可控）
# 保持 IconFile + IconName
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$INFO_PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconName AppIcon" "$INFO_PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$INFO_PLIST"

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
