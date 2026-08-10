import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/io_client.dart';

import '../theme/app_theme.dart';
import '../services/thumbnail_cache.dart';

/// 可见时才加载缩略图的格子；选中态由 [selection] 局部通知，避免整页重建
class LazyThumbTile extends StatefulWidget {
  const LazyThumbTile({
    super.key,
    required this.cacheDeviceKey,
    required this.itemId,
    required this.thumbUrl,
    required this.http,
    required this.selection,
    required this.onTap,
    this.onSecondaryTap,
    this.badge,
    this.bottomLeft,
    this.title,
    this.isVideo = false,
    this.durationLabel,
    this.sizeLabel,
  });

  final String cacheDeviceKey;
  final String itemId;
  final String thumbUrl;
  final IOClient http;

  /// 选中集合；本格子只在自身选中态变化时 setState
  final ValueNotifier<Set<String>> selection;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;
  final Widget? badge;
  final Widget? bottomLeft;
  final String? title;

  /// 视频格子显示播放角标与时长
  final bool isVideo;
  final String? durationLabel;

  /// 文件大小文案（如 1.2 MB）；图片/视频均可显示
  final String? sizeLabel;

  @override
  State<LazyThumbTile> createState() => _LazyThumbTileState();
}

class _LazyThumbTileState extends State<LazyThumbTile> {
  Uint8List? _bytes;
  MemoryImage? _memoryImage;
  bool _loading = false;
  late bool _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selection.value.contains(widget.itemId);
    widget.selection.addListener(_onSelectionChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant LazyThumbTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) {
      oldWidget.selection.removeListener(_onSelectionChanged);
      widget.selection.addListener(_onSelectionChanged);
      _syncSelected();
    } else if (oldWidget.itemId != widget.itemId) {
      _syncSelected();
    }
    if (oldWidget.itemId != widget.itemId ||
        oldWidget.thumbUrl != widget.thumbUrl) {
      _bytes = null;
      _memoryImage = null;
      _load();
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChanged);
    super.dispose();
  }

  /// 仅当本 item 的勾选态翻转时才重建，避免网格全体刷新
  void _onSelectionChanged() => _syncSelected();

  void _syncSelected() {
    final next = widget.selection.value.contains(widget.itemId);
    if (next == _selected || !mounted) return;
    setState(() => _selected = next);
  }

  /// 右下角信息条：视频「时长 · 大小」，图片仅「大小」
  String get _metaBadgeText {
    final parts = <String>[];
    if (widget.isVideo &&
        widget.durationLabel != null &&
        widget.durationLabel!.isNotEmpty) {
      parts.add(widget.durationLabel!);
    }
    if (widget.sizeLabel != null && widget.sizeLabel!.isNotEmpty) {
      parts.add(widget.sizeLabel!);
    }
    return parts.join(' · ');
  }

  Future<void> _load() async {
    if (_loading || _bytes != null) return;
    _loading = true;
    try {
      final cached = await ThumbnailCache.instance
          .get(widget.cacheDeviceKey, widget.itemId);
      if (cached != null) {
        if (mounted) {
          setState(() {
            _bytes = cached;
            _memoryImage = MemoryImage(cached);
          });
        }
        return;
      }
      final res = await widget.http.get(Uri.parse(widget.thumbUrl));
      if (res.statusCode == 200) {
        final bytes = res.bodyBytes;
        await ThumbnailCache.instance
            .put(widget.cacheDeviceKey, widget.itemId, bytes);
        if (mounted) {
          setState(() {
            _bytes = bytes;
            _memoryImage = MemoryImage(bytes);
          });
        }
      }
    } catch (_) {
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 不绑 onDoubleTap：与 onTap 同控件会触发约 300ms 双击判定延迟
    return Material(
      color: Colors.black12,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onSecondaryTap: widget.onSecondaryTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_memoryImage == null)
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Image(
                image: _memoryImage!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
              ),
            if (_selected)
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
                _selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: _selected ? PhotoLinkTheme.brand : Colors.white,
                shadows: const [Shadow(blurRadius: 4, color: Colors.black45)],
              ),
            ),
            // 右下角：视频「时长 · 大小」，图片仅「大小」
            if (_metaBadgeText.isNotEmpty)
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
                    _metaBadgeText,
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
