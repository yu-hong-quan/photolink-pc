import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/io_client.dart';

import '../theme/app_theme.dart';
import '../services/thumbnail_cache.dart';

/// 可见时才加载缩略图的格子，本地 setState，避免整页重建卡顿
class LazyThumbTile extends StatefulWidget {
  const LazyThumbTile({
    super.key,
    required this.cacheDeviceKey,
    required this.itemId,
    required this.thumbUrl,
    required this.http,
    required this.selected,
    required this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.badge,
    this.bottomLeft,
    this.title,
    this.isVideo = false,
    this.durationLabel,
  });

  final String cacheDeviceKey;
  final String itemId;
  final String thumbUrl;
  final IOClient http;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onSecondaryTap;
  final Widget? badge;
  final Widget? bottomLeft;
  final String? title;

  /// 视频格子显示播放角标与时长
  final bool isVideo;
  final String? durationLabel;

  @override
  State<LazyThumbTile> createState() => _LazyThumbTileState();
}

class _LazyThumbTileState extends State<LazyThumbTile> {
  Uint8List? _bytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LazyThumbTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemId != widget.itemId ||
        oldWidget.thumbUrl != widget.thumbUrl) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading || _bytes != null) return;
    _loading = true;
    try {
      final cached = await ThumbnailCache.instance
          .get(widget.cacheDeviceKey, widget.itemId);
      if (cached != null) {
        if (mounted) setState(() => _bytes = cached);
        return;
      }
      final res = await widget.http.get(Uri.parse(widget.thumbUrl));
      if (res.statusCode == 200) {
        final bytes = res.bodyBytes;
        await ThumbnailCache.instance
            .put(widget.cacheDeviceKey, widget.itemId, bytes);
        if (mounted) setState(() => _bytes = bytes);
      }
    } catch (_) {
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black12,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTap: widget.onSecondaryTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_bytes == null)
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Image.memory(
                _bytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
              ),
            if (widget.selected)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: PhotoLinkTheme.brand, width: 3),
                  borderRadius: BorderRadius.circular(14),
                  color: PhotoLinkTheme.brand.withValues(alpha: 0.12),
                ),
              ),
            if (widget.badge != null)
              Positioned(left: 6, top: 6, child: widget.badge!),
            // 视频封面中央播放提示
            if (widget.isVideo)
              const Center(
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white70,
                  size: 36,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                ),
              ),
            Positioned(
              top: 6,
              right: 6,
              child: Icon(
                widget.selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: widget.selected ? PhotoLinkTheme.brand : Colors.white,
                shadows: const [Shadow(blurRadius: 4, color: Colors.black45)],
              ),
            ),
            if (widget.isVideo &&
                widget.durationLabel != null &&
                widget.durationLabel!.isNotEmpty)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.durationLabel!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            if (widget.bottomLeft != null)
              Positioned(left: 4, bottom: 4, child: widget.bottomLeft!),
            if (widget.title != null && widget.title!.isNotEmpty)
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Text(
                  widget.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 自定义相册分类选择器（替代系统 Dropdown）
class AlbumPickerButton extends StatelessWidget {
  const AlbumPickerButton({
    super.key,
    required this.albums,
    required this.albumId,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> albums;
  final String? albumId;
  final ValueChanged<String?> onChanged;

  String get _label {
    if (albumId == null || albumId!.isEmpty) return '全部相册';
    for (final e in albums) {
      if ('${e['id']}' == albumId) {
        return '${e['name']}（${e['count']}）';
      }
    }
    return '全部相册';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showPickerSheet(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: PhotoLinkTheme.brand.withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: PhotoLinkTheme.brand.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.folder_open_rounded,
                size: 18,
                color: PhotoLinkTheme.brand,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  _label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF163A38),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: PhotoLinkTheme.brand.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPickerSheet(BuildContext context) async {
    final options = <({String? id, String name, String? count})>[
      (id: null, name: '全部相册', count: null),
      ...albums.where((e) => e['isAll'] != true).map(
            (e) => (
              id: '${e['id']}' as String?,
              name: '${e['name'] ?? '未命名'}',
              count: '${e['count'] ?? 0}',
            ),
          ),
    ];

    final picked = await showDialog<String?>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) {
        return Dialog(
          alignment: Alignment.topCenter,
          insetPadding: const EdgeInsets.only(top: 120, left: 40, right: 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.photo_album_rounded,
                        color: PhotoLinkTheme.brand,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          '选择相册分类',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final o = options[index];
                      final selected = o.id == albumId;
                      return ListTile(
                        leading: Icon(
                          o.id == null
                              ? Icons.photo_library_rounded
                              : Icons.folder_rounded,
                          color: selected
                              ? PhotoLinkTheme.brand
                              : const Color(0xFF5A6F6D),
                        ),
                        title: Text(
                          o.name,
                          style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600,
                            color: selected
                                ? PhotoLinkTheme.brand
                                : const Color(0xFF163A38),
                          ),
                        ),
                        subtitle: o.count == null
                            ? const Text('显示当前类型下的全部媒体')
                            : Text('${o.count} 项'),
                        trailing: selected
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: PhotoLinkTheme.brand,
                              )
                            : null,
                        onTap: () => Navigator.pop(ctx, o.id ?? ''),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!context.mounted || picked == null) return;
    // '' 表示全部相册
    final next = picked.isEmpty ? null : picked;
    if (next != albumId) onChanged(next);
  }
}
