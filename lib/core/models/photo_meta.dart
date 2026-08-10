/// 媒体类型：与手机端 / API 约定一致（image | video）
class MediaKind {
  static const image = 'image';
  static const video = 'video';

  /// 解析接口或本地值；非法值回退为图片
  static String normalize(String? raw) {
    final v = (raw ?? image).trim().toLowerCase();
    if (v == video || v == 'videos') return video;
    return image;
  }

  /// 根据 mime / 扩展名判断是否为视频
  static bool looksLikeVideo({String? mimeType, String? pathOrName}) {
    final mime = (mimeType ?? '').toLowerCase();
    if (mime.startsWith('video/')) return true;
    final name = (pathOrName ?? '').toLowerCase();
    const exts = [
      '.mp4',
      '.mov',
      '.m4v',
      '.avi',
      '.mkv',
      '.webm',
      '.3gp',
      '.wmv',
    ];
    for (final e in exts) {
      if (name.endsWith(e)) return true;
    }
    return false;
  }

  /// 下载默认扩展名
  static String defaultExtension(String mediaType, {String? mimeType}) {
    if (normalize(mediaType) == video) {
      final mime = (mimeType ?? '').toLowerCase();
      if (mime.contains('quicktime') || mime.contains('mov')) return '.mov';
      if (mime.contains('webm')) return '.webm';
      if (mime.contains('mkv')) return '.mkv';
      if (mime.contains('avi')) return '.avi';
      return '.mp4';
    }
    final mime = (mimeType ?? '').toLowerCase();
    if (mime.contains('png')) return '.png';
    if (mime.contains('webp')) return '.webp';
    if (mime.contains('gif')) return '.gif';
    if (mime.contains('heic') || mime.contains('heif')) return '.heic';
    return '.jpg';
  }
}

/// 相册媒体元数据（仅元数据，不含二进制）
class PhotoMeta {
  const PhotoMeta({
    required this.id,
    required this.width,
    required this.height,
    required this.createTimeMs,
    this.mimeType,
    this.title,
    this.albumId,
    this.albumName,
    this.mediaType = MediaKind.image,
    this.durationMs = 0,
    this.sizeBytes = 0,
  });

  final String id;
  final int width;
  final int height;
  final int createTimeMs;
  final String? mimeType;
  final String? title;
  final String? albumId;
  final String? albumName;

  /// image / video
  final String mediaType;

  /// 视频时长（毫秒）；图片为 0
  final int durationMs;

  /// 原文件占用字节数（手机端上报；旧端可能为 0）
  final int sizeBytes;

  bool get isVideo => MediaKind.normalize(mediaType) == MediaKind.video;

  /// 人类可读的文件大小（B / KB / MB / GB）
  String get sizeLabel => formatFileSize(sizeBytes);

  /// 建议的本地下载文件名（尽量保留标题扩展名）
  String get suggestedFileName {
    final raw = (title ?? '').trim();
    if (raw.isNotEmpty && raw.contains('.')) {
      return raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    }
    final ext = MediaKind.defaultExtension(mediaType, mimeType: mimeType);
    final base = raw.isNotEmpty
        ? raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        : id;
    return '$base$ext';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'width': width,
        'height': height,
        'createTimeMs': createTimeMs,
        'mimeType': mimeType,
        'title': title,
        'albumId': albumId,
        'albumName': albumName,
        'mediaType': mediaType,
        'durationMs': durationMs,
        'sizeBytes': sizeBytes,
      };

  factory PhotoMeta.fromJson(Map<String, dynamic> json) {
    final mime = json['mimeType']?.toString();
    final rawType = json['mediaType']?.toString();
    final mediaType = rawType != null && rawType.isNotEmpty
        ? MediaKind.normalize(rawType)
        : (MediaKind.looksLikeVideo(mimeType: mime)
            ? MediaKind.video
            : MediaKind.image);
    return PhotoMeta(
      id: json['id']?.toString() ?? '',
      width: int.tryParse('${json['width']}') ?? 0,
      height: int.tryParse('${json['height']}') ?? 0,
      createTimeMs: int.tryParse('${json['createTimeMs']}') ?? 0,
      mimeType: mime,
      title: json['title']?.toString(),
      albumId: json['albumId']?.toString(),
      albumName: json['albumName']?.toString(),
      mediaType: mediaType,
      durationMs: int.tryParse('${json['durationMs']}') ?? 0,
      sizeBytes: int.tryParse('${json['sizeBytes']}') ?? 0,
    );
  }
}

/// 将字节数格式化为 B / KB / MB / GB
String formatFileSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    final kb = bytes / 1024;
    return '${kb >= 100 ? kb.toStringAsFixed(0) : kb.toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// PC 端列表排序：默认按时间；可选按文件大小
enum GallerySizeSort {
  /// 不按大小排，保持「最近在前」
  none,

  /// 文件占用从大到小
  sizeDesc,

  /// 文件占用从小到大
  sizeAsc,
}
