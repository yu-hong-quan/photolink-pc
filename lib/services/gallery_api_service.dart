import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  }) async {
    final res = await _client.get('/api/gallery/list', query: {
      'page': '$page',
      'pageSize': '$pageSize',
    });
    if (res.statusCode != 200) {
      throw Exception('拉取相册失败 HTTP ${res.statusCode}');
    }
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final list = (map['list'] as List? ?? [])
        .map((e) => PhotoMeta.fromJson(e as Map<String, dynamic>))
        .toList();
    return (
      list: list,
      total: int.tryParse('${map['total']}') ?? list.length,
      page: page,
    );
  }

  String thumbnailUrl(String photoId) =>
      '${device.baseUrl}/api/gallery/thumbnail/${Uri.encodeComponent(photoId)}';

  /// 流式下载原图；[token] 可中途取消
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
      throw Exception('下载原图失败 HTTP ${streamed.statusCode}');
    }
    final total = streamed.contentLength;
    final name = fileName ?? 'photo_$photoId.jpg';
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

  Future<void> deletePhotos(List<String> photoIds) async {
    final res = await _client.postJson(
      '/api/gallery/delete',
      jsonEncode({'photoIds': photoIds}),
    );
    if (res.statusCode != 200) {
      throw Exception('删除失败 HTTP ${res.statusCode}');
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
