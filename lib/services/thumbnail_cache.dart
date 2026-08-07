import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 缩略图本地磁盘缓存，减少重复请求
class ThumbnailCache {
  ThumbnailCache._();
  static final ThumbnailCache instance = ThumbnailCache._();

  Directory? _root;
  final _memory = <String, Uint8List>{};

  Future<Directory> _ensureRoot() async {
    if (_root != null) return _root!;
    final base = await getApplicationSupportDirectory();
    _root = Directory(p.join(base.path, 'photolink_thumb_cache'));
    if (!await _root!.exists()) {
      await _root!.create(recursive: true);
    }
    return _root!;
  }

  String _key(String deviceId, String photoId) {
    final raw = '$deviceId::$photoId';
    return sha1.convert(utf8.encode(raw)).toString();
  }

  File _fileFor(Directory root, String key) =>
      File(p.join(root.path, '$key.jpg'));

  /// 先读内存，再读磁盘
  Future<Uint8List?> get(String deviceId, String photoId) async {
    final key = _key(deviceId, photoId);
    final mem = _memory[key];
    if (mem != null) return mem;
    final root = await _ensureRoot();
    final file = _fileFor(root, key);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    _memory[key] = bytes;
    return bytes;
  }

  Future<void> put(String deviceId, String photoId, Uint8List bytes) async {
    final key = _key(deviceId, photoId);
    _memory[key] = bytes;
    final root = await _ensureRoot();
    final file = _fileFor(root, key);
    await file.writeAsBytes(bytes, flush: true);
  }

  /// 彻底删除后清理本地缩略图，避免 PC 端继续展示已销毁图片
  Future<void> remove(String deviceId, String photoId) async {
    final key = _key(deviceId, photoId);
    _memory.remove(key);
    final root = await _ensureRoot();
    final file = _fileFor(root, key);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  /// 可选：清理过期缓存（默认 7 天）
  Future<void> purgeOlderThan({Duration maxAge = const Duration(days: 7)}) async {
    final root = await _ensureRoot();
    final cutoff = DateTime.now().subtract(maxAge);
    await for (final entity in root.list()) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }
}
