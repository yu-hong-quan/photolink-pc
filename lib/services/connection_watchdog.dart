import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/models/device_info.dart';
import 'gallery_api_service.dart';

/// 连接心跳：周期性探测手机端，断连时通知 UI
class ConnectionWatchdog extends ChangeNotifier {
  ConnectionWatchdog({
    required this.device,
    this.interval = const Duration(seconds: 5),
    this.failThreshold = 2,
  });

  final DeviceInfoModel device;
  final Duration interval;
  final int failThreshold;

  GalleryApiService? _api;
  Timer? _timer;
  int _failCount = 0;
  bool _connected = true;
  bool _disposed = false;
  String? _lastError;

  bool get isConnected => _connected;
  String? get lastError => _lastError;

  void start() {
    _api ??= GalleryApiService(device);
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick());
    // 立即探测一次
    unawaited(_tick());
  }

  Future<void> _tick() async {
    if (_disposed) return;
    try {
      await _api!.fetchDeviceInfo();
      _failCount = 0;
      _lastError = null;
      if (!_connected) {
        _connected = true;
        notifyListeners();
      }
    } catch (e) {
      _failCount += 1;
      _lastError = '$e';
      if (_failCount >= failThreshold && _connected) {
        _connected = false;
        notifyListeners();
      }
    }
  }

  /// 手动立即重连探测
  Future<bool> probeNow() async {
    try {
      _api ??= GalleryApiService(device);
      await _api!.fetchDeviceInfo();
      _failCount = 0;
      _lastError = null;
      _connected = true;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = '$e';
      _connected = false;
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _api?.close();
    super.dispose();
  }
}
