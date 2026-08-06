import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/models/device_info.dart';

/// PC 端 mDNS 发现：监听局域网内手机 PhotoLink 服务
class MdnsDiscoveryService {
  BonsoirDiscovery? _discovery;
  final _devices = <String, DeviceInfoModel>{};
  final _controller = StreamController<List<DeviceInfoModel>>.broadcast();

  Stream<List<DeviceInfoModel>> get devicesStream => _controller.stream;
  List<DeviceInfoModel> get devices => _devices.values.toList();

  Future<void> start() async {
    await stop();
    _discovery = BonsoirDiscovery(type: PhotoLinkConst.mdnsType);
    await _discovery!.ready;

    _discovery!.eventStream?.listen((event) {
      final service = event.service;
      if (service == null) return;

      if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
        // 解析 IP/端口
        service.resolve(_discovery!.serviceResolver);
      } else if (event.type ==
          BonsoirDiscoveryEventType.discoveryServiceResolved) {
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
        _devices[info.deviceId.isNotEmpty ? info.deviceId : info.ip] = info;
        _emit();
        debugPrint('发现设备: ${info.deviceName} ${info.ip}:${info.port}');
      } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceLost) {
        final key = service.attributes['deviceId'] ?? service.name;
        _devices.remove(key);
        _devices.removeWhere((k, v) => v.deviceName == service.name);
        _emit();
      }
    });

    await _discovery!.start();
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(devices);
    }
  }

  Future<void> stop() async {
    try {
      await _discovery?.stop();
    } catch (_) {}
    _discovery = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
