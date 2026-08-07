/// 运行环境：通过 `--dart-define=FLAVOR=local|test|prod` 注入
///
/// 三套环境使用不同端口，避免本机同时调试时冲突。
enum AppFlavor { local, test, prod }

/// App / PC 共用的环境配置读取入口
class AppEnv {
  AppEnv._();

  /// 编译期注入，默认生产
  static const String flavorName =
      String.fromEnvironment('FLAVOR', defaultValue: 'prod');

  static AppFlavor get flavor {
    switch (flavorName.toLowerCase()) {
      case 'local':
      case 'dev':
        return AppFlavor.local;
      case 'test':
      case 'staging':
        return AppFlavor.test;
      default:
        return AppFlavor.prod;
    }
  }

  static String get flavorLabel {
    switch (flavor) {
      case AppFlavor.local:
        return '本地环境';
      case AppFlavor.test:
        return '测试环境';
      case AppFlavor.prod:
        return '生产环境';
    }
  }

  /// 手机相册 HTTPS 端口
  static int get galleryPort {
    switch (flavor) {
      case AppFlavor.local:
        return 53337;
      case AppFlavor.test:
        return 53327;
      case AppFlavor.prod:
        return 53317;
    }
  }

  /// PC 配对 HTTPS 端口
  static int get pairPort {
    switch (flavor) {
      case AppFlavor.local:
        return 53338;
      case AppFlavor.test:
        return 53328;
      case AppFlavor.prod:
        return 53318;
    }
  }

  /// 非生产显示调试角标
  static bool get showDebugBanner => flavor != AppFlavor.prod;
}
