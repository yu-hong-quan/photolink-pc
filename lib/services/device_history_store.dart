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

  /// 同一物理设备：deviceId 相同，或 IP 相同（扫码/手动可能 key 不一致）
  static bool isSameDevice(DeviceInfoModel a, DeviceInfoModel b) {
    if (a.deviceId.isNotEmpty &&
        b.deviceId.isNotEmpty &&
        a.deviceId == b.deviceId) {
      return true;
    }
    if (a.ip.isNotEmpty && a.ip == b.ip) return true;
    return false;
  }

  /// 同一设备只保留最近一条连接记录
  List<DeviceHistoryEntry> _dedupeKeepLatest(List<DeviceHistoryEntry> input) {
    final sorted = [...input]
      ..sort((a, b) => b.lastConnectedAtMs.compareTo(a.lastConnectedAtMs));
    final result = <DeviceHistoryEntry>[];
    for (final e in sorted) {
      final exists = result.any((x) => isSameDevice(x.device, e.device));
      if (!exists) result.add(e);
    }
    return result;
  }

  Future<List<DeviceHistoryEntry>> load() async {
    final file = await _ensureFile();
    if (!await file.exists()) return [];
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      final list = raw
          .map((e) => DeviceHistoryEntry.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .where((e) => e.device.ip.isNotEmpty)
          .toList();
      final deduped = _dedupeKeepLatest(list);
      // 历史里若有重复，写回清洗后的列表
      if (deduped.length != list.length) {
        await _save(deduped);
      }
      return deduped;
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

  /// 连接成功或扫码配对后写入/更新记录（同一设备覆盖为最新一条）
  Future<List<DeviceHistoryEntry>> upsert(
    DeviceInfoModel device, {
    bool markConnected = true,
  }) async {
    final list = await load();
    final now = DateTime.now().millisecondsSinceEpoch;
    // 先去掉同一设备的旧记录，再插入最新
    list.removeWhere((e) => isSameDevice(e.device, device));
    list.insert(
      0,
      DeviceHistoryEntry(
        device: device,
        lastConnectedAtMs: markConnected ? now : 0,
        lastSeenAtMs: now,
      ),
    );
    final deduped = _dedupeKeepLatest(list);
    await _save(deduped);
    return deduped;
  }

  Future<List<DeviceHistoryEntry>> remove(String key) async {
    final list = await load();
    list.removeWhere((e) => keyOf(e.device) == key);
    await _save(list);
    return list;
  }
}
