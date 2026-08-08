import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../core/constants.dart';
import '../core/models/device_info.dart';
import '../core/models/photo_meta.dart';
import 'api_client.dart';
import 'transfer_task_queue.dart';

/// 面向手机端相册 API 的业务封装（支持取消令牌）
class GalleryApiService {
  GalleryApiService(this.device) : _client = PhotoLinkApiClient(device.baseUrl);

  final DeviceInfoModel device;
  final PhotoLinkApiClient _client;

  void close() => _client.close();

  Future<DeviceInfoModel> fetchDeviceInfo() async {
    final res = await _client.get('/api/device/info');
    if (res.statusCode != 200) {
      throw Exception('连接失败 HTTP ${res.statusCode}');
    }
    return DeviceInfoModel.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<({List<PhotoMeta> list, int total, int page})> listPhotos({
    int page = 0,
    int pageSize = PhotoLinkConst.defaultPageSize,
    String? albumId,
    String mediaType = MediaKind.image,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      // 与手机端约定：image | video（分栏管理）
      'mediaType': MediaKind.normalize(mediaType),
    };
    if (albumId != null && albumId.isNotEmpty) {
      query['albumId'] = albumId;
    }
    final res = await _client.get('/api/gallery/list', query: query);
    if (res.statusCode != 200) {
      throw Exception('拉取相册失败 HTTP ${res.statusCode}');
    }
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final list = (map['list'] as List? ?? [])
        .map((e) => PhotoMeta.fromJson(e as Map<String, dynamic>))
        .toList();
    // 客户端兜底：最近的在前
    list.sort((a, b) => b.createTimeMs.compareTo(a.createTimeMs));
    return (
      list: list,
      total: int.tryParse('${map['total']}') ?? list.length,
      page: page,
    );
  }

  Future<List<Map<String, dynamic>>> listAlbums({
    String mediaType = MediaKind.image,
  }) async {
    final res = await _client.get(
      '/api/gallery/albums',
      query: {'mediaType': MediaKind.normalize(mediaType)},
    );
    if (res.statusCode != 200) {
      throw Exception('拉取相册分类失败 HTTP ${res.statusCode}');
    }
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (map['list'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  String thumbnailUrl(String photoId) =>
      '${device.baseUrl}/api/gallery/thumbnail/${Uri.encodeComponent(photoId)}';

  String originalUrl(String photoId) =>
      '${device.baseUrl}/api/gallery/original/${Uri.encodeComponent(photoId)}';

  /// 预览用：拉取原图字节（带简单超时；大图由调用方注意内存；视频勿用）
  Future<Uint8List> fetchOriginalBytes(String photoId) async {
    final streamed = await _client.getStream(
      '/api/gallery/original/${Uri.encodeComponent(photoId)}',
    );
    if (streamed.statusCode != 200) {
      throw Exception('预览原图失败 HTTP ${streamed.statusCode}');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// 流式下载原文件；[token] 可中途取消
  Future<File> downloadOriginal({
    required String photoId,
    required Directory saveDir,
    String? fileName,
    void Function(int received, int? total)? onProgress,
    CancelToken? token,
  }) async {
    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }
    token?.throwIfCancelled();
    final streamed = await _client.getStream(
      '/api/gallery/original/${Uri.encodeComponent(photoId)}',
    );
    if (streamed.statusCode != 200) {
      throw Exception('下载失败 HTTP ${streamed.statusCode}');
    }
    final total = streamed.contentLength;
    // 优先用 Content-Disposition 文件名，否则用调用方传入名
    final fromHeader = _fileNameFromContentDisposition(
      streamed.headers['content-disposition'],
    );
    final name = fileName ?? fromHeader ?? 'media_$photoId.bin';
    final file = File(p.join(saveDir.path, name));
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream) {
        token?.throwIfCancelled();
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      return file;
    } catch (e) {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  String? _fileNameFromContentDisposition(String? header) {
    if (header == null || header.isEmpty) return null;
    // 解析 attachment; filename="xxx.mp4"
    final match = RegExp(
      r'filename="?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(header);
    if (match == null) return null;
    try {
      return p.basename(Uri.decodeComponent(match.group(1)!.trim()));
    } catch (_) {
      return p.basename(match.group(1)!.trim());
    }
  }

  /// 软删除（进回收站；需手机端确认，超时放宽到 2.5 分钟）
  Future<void> deletePhotos(List<String> photoIds) async {
    final res = await _client.postJson(
      '/api/gallery/delete',
      jsonEncode({'photoIds': photoIds}),
      timeout: const Duration(minutes: 2, seconds: 30),
    );
    if (res.statusCode == 403) {
      throw Exception('手机端拒绝或未确认删除');
    }
    if (res.statusCode != 200) {
      throw Exception('删除失败 HTTP ${res.statusCode}');
    }
  }

  Future<void> renamePhoto(String photoId, String title) async {
    final res = await _client.postJson(
      '/api/gallery/rename',
      jsonEncode({'photoId': photoId, 'title': title}),
    );
    if (res.statusCode != 200) {
      throw Exception('重命名失败 HTTP ${res.statusCode}');
    }
  }

  Future<void> categorizePhotos({
    required List<String> photoIds,
    required String albumName,
  }) async {
    final res = await _client.postJson(
      '/api/gallery/categorize',
      jsonEncode({'photoIds': photoIds, 'albumName': albumName}),
    );
    if (res.statusCode != 200) {
      throw Exception('归类失败 HTTP ${res.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> listTrash() async {
    final res = await _client.get('/api/trash/list');
    if (res.statusCode != 200) {
      throw Exception('拉取回收站失败 HTTP ${res.statusCode}');
    }
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (map['list'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  String trashThumbUrl(String trashId) =>
      '${device.baseUrl}/api/trash/thumbnail/${Uri.encodeComponent(trashId)}';

  Future<void> restoreTrash(List<String> trashIds) async {
    final res = await _client.postJson(
      '/api/trash/restore',
      jsonEncode({'trashIds': trashIds}),
    );
    if (res.statusCode != 200) {
      throw Exception('恢复失败 HTTP ${res.statusCode}');
    }
  }

  Future<void> purgeTrash(List<String> trashIds) async {
    final res = await _client.postJson(
      '/api/trash/purge',
      jsonEncode({'trashIds': trashIds}),
    );
    if (res.statusCode != 200) {
      throw Exception('彻底删除失败 HTTP ${res.statusCode}');
    }
  }

  /// 流式上传；[token] 可中途取消
  Future<void> uploadFile(
    File file, {
    void Function(int sent, int total)? onProgress,
    CancelToken? token,
  }) async {
    token?.throwIfCancelled();
    final length = await file.length();
    final name = p.basename(file.path);
    var sent = 0;
    final controller = StreamController<List<int>>();

    // 边读边检查取消，再喂给 HTTP 请求
    unawaited(() async {
      try {
        await for (final chunk in file.openRead()) {
          token?.throwIfCancelled();
          controller.add(chunk);
          sent += chunk.length;
          onProgress?.call(sent, length);
        }
        await controller.close();
      } catch (e, st) {
        controller.addError(e, st);
        await controller.close();
      }
    }());

    final streamed = await _client.postBytesStream(
      path: '/api/gallery/upload',
      stream: controller.stream,
      contentLength: length,
      fileName: name,
      contentType: 'application/octet-stream',
    );
    final body = await streamed.stream.bytesToString();
    token?.throwIfCancelled();
    if (streamed.statusCode != 200) {
      throw Exception('上传失败 HTTP ${streamed.statusCode}: $body');
    }
  }
}
