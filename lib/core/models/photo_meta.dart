/// 相册照片元数据（仅元数据，不含二进制）
class PhotoMeta {
  const PhotoMeta({
    required this.id,
    required this.width,
    required this.height,
    required this.createTimeMs,
    this.mimeType,
    this.title,
  });

  final String id;
  final int width;
  final int height;
  final int createTimeMs;
  final String? mimeType;
  final String? title;

  Map<String, dynamic> toJson() => {
        'id': id,
        'width': width,
        'height': height,
        'createTimeMs': createTimeMs,
        'mimeType': mimeType,
        'title': title,
      };

  factory PhotoMeta.fromJson(Map<String, dynamic> json) {
    return PhotoMeta(
      id: json['id']?.toString() ?? '',
      width: int.tryParse('${json['width']}') ?? 0,
      height: int.tryParse('${json['height']}') ?? 0,
      createTimeMs: int.tryParse('${json['createTimeMs']}') ?? 0,
      mimeType: json['mimeType']?.toString(),
      title: json['title']?.toString(),
    );
  }
}
