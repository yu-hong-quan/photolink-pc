/// 设备信息（/api/device/info 与 mDNS TXT 共用）
class DeviceInfoModel {
  const DeviceInfoModel({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.osVersion,
    required this.ip,
    required this.port,
  });

  final String deviceId;
  final String deviceName;

  /// phone / pc
  final String deviceType;
  final String osVersion;
  final String ip;
  final int port;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'deviceType': deviceType,
        'osVersion': osVersion,
        'ip': ip,
        'port': port,
      };

  factory DeviceInfoModel.fromJson(Map<String, dynamic> json) {
    return DeviceInfoModel(
      deviceId: json['deviceId']?.toString() ?? '',
      deviceName: json['deviceName']?.toString() ?? '未知设备',
      deviceType: json['deviceType']?.toString() ?? 'phone',
      osVersion: json['osVersion']?.toString() ?? '',
      ip: json['ip']?.toString() ?? '',
      port: int.tryParse('${json['port']}') ?? 53317,
    );
  }

  /// 手机端连接串（旧兜底：PC 粘贴手机二维码内容）
  String toConnectPayload() => 'photolink://$ip:$port?id=$deviceId&name=$deviceName';

  /// PC 端展示给 App 扫描的配对二维码内容
  String toPcPairPayload() =>
      'photolink-pc://$ip:$port?id=$deviceId&name=${Uri.encodeComponent(deviceName)}';

  static DeviceInfoModel? fromConnectPayload(String raw) {
    final text = raw.trim();
    if (!text.startsWith('photolink://')) return null;
    try {
      final uri = Uri.parse(text);
      return DeviceInfoModel(
        deviceId: uri.queryParameters['id'] ?? '',
        deviceName: uri.queryParameters['name'] ?? '手机设备',
        deviceType: 'phone',
        osVersion: '',
        ip: uri.host,
        port: uri.hasPort ? uri.port : 53317,
      );
    } catch (_) {
      return null;
    }
  }

  /// 解析 PC 配对二维码（App 扫码用）
  static DeviceInfoModel? fromPcPairPayload(String raw) {
    final text = raw.trim();
    if (!text.startsWith('photolink-pc://')) return null;
    try {
      final uri = Uri.parse(text);
      return DeviceInfoModel(
        deviceId: uri.queryParameters['id'] ?? '',
        deviceName: Uri.decodeComponent(
          uri.queryParameters['name'] ?? '电脑',
        ),
        deviceType: 'pc',
        osVersion: '',
        ip: uri.host,
        port: uri.hasPort ? uri.port : 53318,
      );
    } catch (_) {
      return null;
    }
  }

  String get baseUrl => 'https://$ip:$port';
}
