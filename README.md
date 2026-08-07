# PhotoLink PC（图联 · 桌面端）

局域网发现手机、浏览相册、下载原图、删除、拖拽上传；同时广播本机配对服务供手机主动发现。

## 运行

```bash
flutter pub get
# 本地环境
flutter run -d windows --dart-define=FLAVOR=local
# 或
.\scripts\run-windows.ps1 -Env local
./scripts/run-macos.sh local
```

## 打包（local / test / prod）

| 环境 | 相册端口 | 配对端口 |
|------|----------|----------|
| local | 53337 | 53338 |
| test | 53327 | 53328 |
| prod | 53317 | 53318 |

```bash
# Windows
.\scripts\build-windows.cmd prod
# 或 .\scripts\build-windows.ps1 -Env test

# macOS（需在 Mac 上）
./scripts/build-macos.sh prod
```

产物：
- Windows：`build/windows/x64/runner/Release/photolink_pc.exe`（整目录分发）
- macOS：`build/macos/Build/Products/Release/photolink_pc.app`

**注意：电脑与手机必须使用同一 FLAVOR。**

## 目录

- `lib/services/mdns_discovery_service.dart` — 发现手机
- `lib/services/mdns_advertise_service.dart` — 广播本机给手机搜
- `lib/pages/about_page.dart` — 作者信息
- `scripts/` — 多环境运行 / 打包脚本
