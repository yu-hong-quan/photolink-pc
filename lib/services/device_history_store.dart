import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/models/device_info.dart';

/// 本地持久化的连接记录（与实时发现列表分离）
class DeviceHistoryEntry {
  DeviceHistoryEntry({
    required this.device,
    required this.lastConnectedAtMs,
    this.lastSeenAtMs,
  });

  DeviceInfoModel device;
  int lastConnectedAtMs;
  int? lastSeenAtMs;

  Map<String, dynamic> toJson() => {
        'device': device.toJson(),
        'lastConnectedAtMs': lastConnectedAtMs,
        'lastSeenAtMs': lastSeenAtMs,
      };

  factory DeviceHistoryEntry.fromJson(Map<String, dynamic> json) {
    return DeviceHistoryEntry(
      device: DeviceInfoModel.fromJson(
        Map<String, dynamic>.from(json['device'] as Map? ?? {}),
      ),
      lastConnectedAtMs: int.tryParse('${json['lastConnectedAtMs']}') ?? 0,
      lastSeenAtMs: int.tryParse('${json['lastSeenAtMs']}'),
    );
  }
}

/// 设备连接记录存储（JSON 文件）
class DeviceHistoryStore {
  DeviceHistoryStore._();
  static final DeviceHistoryStore instance = DeviceHistoryStore._();

  File? _file;

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    _file = File(p.join(dir.path, 'device_history.json'));
    return _file!;
  }

  static String keyOf(DeviceInfoModel d) =>
      d.deviceId.isNotEmpty ? d.deviceId : '${d.ip}:${d.port}';

  Future<List<DeviceHistoryEntry>> load() async {
    final file = await _ensureFile();
    if (!await file.exists()) return [];
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      return raw
          .map((e) => DeviceHistoryEntry.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .where((e) => e.device.ip.isNotEmpty)
          .toList()
        ..sort((a, b) => b.lastConnectedAtMs.compareTo(a.lastConnectedAtMs));
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<DeviceHistoryEntry> list) async {
    final file = await _ensureFile();
    await file.writeAsString(
      jsonEncode(list.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }

  /// 连接成功或扫码配对后写入/更新记录
  Future<List<DeviceHistoryEntry>> upsert(
    DeviceInfoModel device, {
    bool markConnected = true,
  }) async {
    final list = await load();
    final key = keyOf(device);
    final now = DateTime.now().millisecondsSinceEpoch;
    final idx = list.indexWhere((e) => keyOf(e.device) == key);
    if (idx >= 0) {
      list[idx].device = device;
      list[idx].lastSeenAtMs = now;
      if (markConnected) list[idx].lastConnectedAtMs = now;
    } else {
      list.add(
        DeviceHistoryEntry(
          device: device,
          lastConnectedAtMs: markConnected ? now : 0,
          lastSeenAtMs: now,
        ),
      );
    }
    list.sort((a, b) => b.lastConnectedAtMs.compareTo(a.lastConnectedAtMs));
    await _save(list);
    return list;
  }

  Future<List<DeviceHistoryEntry>> remove(String key) async {
    final list = await load();
    list.removeWhere((e) => keyOf(e.device) == key);
    await _save(list);
    return list;
  }
}
