import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/models/device_info.dart';

/// PC 端 mDNS 发现：监听局域网内手机 PhotoLink 服务
class MdnsDiscoveryService {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _eventSub;
  final _devices = <String, DeviceInfoModel>{};
  final _controller = StreamController<List<DeviceInfoModel>>.broadcast();
  bool _starting = false;
  /// start 进行中又收到重启请求时，结束后再跑一轮
  bool _restartQueued = false;

  Stream<List<DeviceInfoModel>> get devicesStream => _controller.stream;
  List<DeviceInfoModel> get devices => _devices.values.toList();

  /// [preserveCache]：重启时保留已发现设备，避免二次扫描瞬间把列表刷空
  Future<void> start({bool preserveCache = false}) async {
    if (_starting) {
      _restartQueued = true;
      return;
    }
    _starting = true;
    try {
      await stop();
      if (!preserveCache) {
        _devices.clear();
        _emit();
      }

      _discovery = BonsoirDiscovery(type: PhotoLinkConst.mdnsType);
      await _discovery!.ready;

      final stream = _discovery!.eventStream;
      if (stream == null) {
        // Windows 偶发 ready 后仍无 stream，交由上层定时重试
        debugPrint('mDNS eventStream 为空，跳过本轮');
        return;
      }
      // 必须在 start 前挂监听，否则 Windows 上早期事件会丢
      _eventSub = stream.listen(_onEvent);
      await _discovery!.start();
      debugPrint('mDNS 发现已启动: ${PhotoLinkConst.mdnsType}');
    } finally {
      _starting = false;
      if (_restartQueued) {
        _restartQueued = false;
        // 保留缓存的强制重启，避免首扫空结果后二次仍被清榜
        unawaited(start(preserveCache: true));
      }
    }
  }

  void _onEvent(BonsoirDiscoveryEvent event) {
    final service = event.service;
    if (service == null) return;

    if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
      service.resolve(_discovery!.serviceResolver);
    } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
      if (service is! ResolvedBonsoirService) return;
      final host = service.host;
      if (host == null || host.isEmpty) return;
      final attrs = service.attributes;
      final info = DeviceInfoModel(
        deviceId: attrs['deviceId'] ?? service.name,
        deviceName: service.name,
        deviceType: attrs['deviceType'] ?? 'phone',
        osVersion: attrs['osVersion'] ?? '',
        ip: (attrs['ip']?.isNotEmpty == true) ? attrs['ip']! : host,
        port: service.port,
      );
      if (info.deviceType == 'pc') return;
      final key = info.deviceId.isNotEmpty ? info.deviceId : info.ip;
      _devices[key] = info;
      _emit();
      debugPrint('发现设备: ${info.deviceName} ${info.ip}:${info.port}');
    } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceLost) {
      final key = service.attributes['deviceId'] ?? service.name;
      _devices.remove(key);
      _devices.removeWhere((k, v) => v.deviceName == service.name);
      _emit();
    }
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(List<DeviceInfoModel>.from(devices));
    }
  }

  /// 强制重启发现（Windows 首次打开常需二次启动才出结果）
  Future<void> restart() async {
    await start(preserveCache: true);
  }

  Future<void> stop() async {
    try {
      await _eventSub?.cancel();
    } catch (_) {}
    _eventSub = null;
    try {
      await _discovery?.stop();
    } catch (_) {}
    _discovery = null;
  }

  Future<void> dispose() async {
    _restartQueued = false;
    await stop();
    await _controller.close();
  }
}
