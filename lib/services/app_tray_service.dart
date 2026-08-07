import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// PC 系统托盘：显示窗口 / 隐藏到托盘 / 退出
class AppTrayService with TrayListener, WindowListener {
  AppTrayService._();
  static final AppTrayService instance = AppTrayService._();

  bool _ready = false;
  bool _exiting = false;

  Future<void> init() async {
    if (kIsWeb || !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return;
    }
    if (_ready) return;

    trayManager.addListener(this);
    windowManager.addListener(this);
    // 点关闭时隐藏到托盘，而不是直接退出
    await windowManager.setPreventClose(true);

    final iconPath = Platform.isWindows
        ? 'assets/icons/tray_icon.ico'
        : 'assets/icons/tray_icon.png';
    await trayManager.setIcon(iconPath);
    await trayManager.setToolTip('PhotoLink · 图联');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: '显示主窗口'),
          MenuItem(key: 'hide', label: '隐藏到托盘'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '退出'),
        ],
      ),
    );
    _ready = true;
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hideToTray() async {
    await windowManager.hide();
  }

  Future<void> exitApp() async {
    if (_exiting) return;
    _exiting = true;
    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onTrayIconMouseDown() {
    // 左键单击：显示窗口
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // Windows 右键弹出菜单
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        showWindow();
        break;
      case 'hide':
        hideToTray();
        break;
      case 'exit':
        exitApp();
        break;
    }
  }

  @override
  void onWindowClose() {
    // 关闭按钮 → 隐藏到托盘
    hideToTray();
  }

  void dispose() {
    if (!_ready) return;
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _ready = false;
  }
}
