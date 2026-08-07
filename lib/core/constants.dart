import 'app_env.dart';

/// PhotoLink 全局常量（与手机端保持一致）
class PhotoLinkConst {
  PhotoLinkConst._();

  /// 手机端相册 HTTPS 服务端口（随 FLAVOR 变化）
  static int get port => AppEnv.galleryPort;

  /// PC 端配对服务端口（展示二维码 / mDNS，供 App 回传手机地址）
  static int get pairPort => AppEnv.pairPort;

  /// mDNS 服务类型（Bonjour/NSD）；phone / pc 靠 TXT deviceType 区分
  static const String mdnsType = '_photolink._tcp';

  /// 产品名
  static const String appName = 'PhotoLink';

  /// 中文简称
  static const String appNameZh = '图联';

  /// 默认分页大小
  static const int defaultPageSize = 60;

  /// 作者信息（关于页展示）
  static const String authorName = '余洪全';
  static const String authorId = 'yu-hong-quan';
  static const String authorGithub = 'https://github.com/yu-hong-quan';
  static const String authorEmail = '';
  static const String productDesc =
      '局域网相册互联工具：手机提供相册服务，电脑发现并浏览、下载与整理。';
}
