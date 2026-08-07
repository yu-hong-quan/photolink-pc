import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/constants.dart';
import 'pages/device_list_page.dart';
import 'services/app_tray_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(1180, 760),
    minimumSize: Size(980, 640),
    center: true,
    title: 'PhotoLink · 图联',
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
      debugShowCheckedModeBanner: false,
      theme: PhotoLinkTheme.light(),
      home: const DeviceListPage(),
    );
  }
}
