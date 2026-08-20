# 发布产物说明

正式安装包（本仓库 `releases/`）：

- Windows Setup：  
  [PhotoLink-Setup-1.1.1-prod.exe](./PhotoLink-Setup-1.1.1-prod.exe)
- macOS DMG：  
  [PhotoLink-1.1.5-prod-macos.dmg](./PhotoLink-1.1.5-prod-macos.dmg)

配套手机端（[photolink-app](https://github.com/yu-hong-quan/photolink-app)）：

- Android APK（arm64）：  
  https://github.com/yu-hong-quan/photolink-app/releases/download/v1.1.1/PhotoLink-1.1.1-prod-arm64.apk
- **iOS**：暂无公开安装包（Apple 不允许像 APK 一样任意分发 IPA；请用 Android，或自行 Xcode / Flutter 签名安装）

本地重新打包：

```bash
# Windows Setup（需 Inno Setup，在 Windows 上）
.\scripts\build-windows-installer.ps1 -EnvName prod

# macOS DMG（需在 Mac 上）
./scripts/build-macos-dmg.sh prod
```
