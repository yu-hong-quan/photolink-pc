import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/models/device_info.dart';

/// PC 端 mDNS 广播：让手机主动发现本机配对服务
class MdnsAdvertiseService {
  BonsoirService? _service;
  BonsoirBroadcast? _broadcast;

  bool get isAdvertising => _broadcast != null;

  /// 发布 `_photolink._tcp`，TXT 标明 deviceType=pc，port 为配对口
  Future<void> start(DeviceInfoModel info) async {
    await stop();
    _service = BonsoirService(
      name: info.deviceName,
      type: PhotoLinkConst.mdnsType,
      port: info.port,
      attributes: {
        'deviceId': info.deviceId,
        'deviceType': 'pc',
        'osVersion': info.osVersion,
        'ip': info.ip,
      },
    );
    _broadcast = BonsoirBroadcast(service: _service!);
    await _broadcast!.ready;
    await _broadcast!.start();
    debugPrint('PC mDNS 广播已启动: ${info.deviceName} ${info.ip}:${info.port}');
  }

  Future<void> stop() async {
    try {
      await _broadcast?.stop();
    } catch (_) {}
    _broadcast = null;
    _service = null;
  }
}
