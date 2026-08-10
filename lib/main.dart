import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/app_env.dart';
import 'core/constants.dart';
import 'pages/device_list_page.dart';
import 'services/app_tray_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final title =
      'PhotoLink · 图联${AppEnv.flavor == AppFlavor.prod ? '' : ' · ${AppEnv.flavorLabel}'}';
  final options = WindowOptions(
    // 默认稍大，相册网格与任务区更舒展
    size: const Size(1320, 860),
    minimumSize: const Size(1040, 700),
    center: true,
    title: title,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // 系统托盘：显示 / 隐藏 / 退出
  await AppTrayService.instance.init();

  runApp(const PhotoLinkPcApp());
}

class PhotoLinkPcApp extends StatelessWidget {
  const PhotoLinkPcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '${PhotoLinkConst.appName} · ${PhotoLinkConst.appNameZh}',
      debugShowCheckedModeBanner: AppEnv.showDebugBanner,
      theme: PhotoLinkTheme.light(),
      home: const DeviceListPage(),
    );
  }
}
