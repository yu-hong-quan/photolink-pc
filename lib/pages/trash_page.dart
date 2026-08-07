import 'package:flutter/material.dart';
import 'package:http/io_client.dart';

import '../core/models/device_info.dart';
import '../services/api_client.dart';
import '../services/gallery_api_service.dart';
import '../services/thumbnail_cache.dart';
import '../widgets/lazy_thumb_tile.dart';

/// 回收站：查看软删图片、恢复、彻底删除（彻底删除后 PC 也不留存缩略图）
class TrashPage extends StatefulWidget {
  const TrashPage({
    super.key,
    required this.device,
    required this.deviceKey,
  });

  final DeviceInfoModel device;
  final String deviceKey;

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  late final GalleryApiService _api;
  late final IOClient _http;
  final _items = <Map<String, dynamic>>[];
  final _selected = <String>{};
  bool _loading = true;
  String? _error;

  /// 回收站缩略图缓存命名空间，与相册原图 id 隔离
  String get _trashCacheDevice => '${widget.deviceKey}::trash';

  @override
  void initState() {
    super.initState();
    _api = GalleryApiService(widget.device);
    _http = createPhotoLinkHttpClient();
    _reload();
  }

  @override
  void dispose() {
    _http.close();
    _api.close();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _selected.clear();
    });
    try {
      final list = await _api.listTrash();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(list);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 全选 / 取消全选回收站全部条目
  void _toggleSelectAll() {
    setState(() {
      final allIds = _items.map((e) => '${e['id']}').toSet();
      final allSelected =
          allIds.isNotEmpty && allIds.every(_selected.contains);
      if (allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(allIds);
      }
    });
  }

  bool get _allSelected {
    if (_items.isEmpty) return false;
    return _items.every((e) => _selected.contains('${e['id']}'));
  }

  Future<void> _restore() async {
    if (_selected.isEmpty) return;
    try {
      await _api.restoreTrash(_selected.toList());
      _toast('已恢复 ${_selected.length} 张到相册');
      await _reload();
    } catch (e) {
      _toast('恢复失败：$e');
    }
  }

  Future<void> _purge() async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除'),
        content: Text(
          '将永久删除 ${_selected.length} 张图片，手机与电脑均不再保留，无法撤回。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final ids = _selected.toList();
      // 彻底删除前记下原图 id，清掉 PC 本地缩略图（不留存）
      final photoIds = _items
          .where((e) => ids.contains('${e['id']}'))
          .map((e) => '${e['originalPhotoId'] ?? ''}')
          .where((e) => e.isNotEmpty)
          .toList();
      await _api.purgeTrash(ids);
      for (final photoId in photoIds) {
        await ThumbnailCache.instance.remove(widget.deviceKey, photoId);
      }
      for (final trashId in ids) {
        await ThumbnailCache.instance.remove(_trashCacheDevice, trashId);
      }
      _toast('已彻底删除');
      await _reload();
    } catch (e) {
      _toast('彻底删除失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7F6),
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          if (_items.isNotEmpty)
            TextButton.icon(
              onPressed: _toggleSelectAll,
              icon: Icon(
                _allSelected
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
              ),
              label: Text(_allSelected ? '取消全选' : '全选'),
            ),
          if (_selected.isNotEmpty) ...[
            TextButton.icon(
              onPressed: _restore,
              icon: const Icon(Icons.restore_rounded),
              label: Text('撤回(${_selected.length})'),
            ),
            TextButton.icon(
              onPressed: _purge,
              icon: const Icon(Icons.delete_forever_rounded),
              label: Text('彻底删除(${_selected.length})'),
            ),
          ],
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _reload, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          '回收站为空',
          style: TextStyle(color: Color(0xFF5A6F6D)),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      cacheExtent: 280,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final trashId = '${item['id']}';
        final title = '${item['title'] ?? trashId}';
        final selected = _selected.contains(trashId);
        return RepaintBoundary(
          child: LazyThumbTile(
            key: ValueKey(trashId),
            cacheDeviceKey: _trashCacheDevice,
            itemId: trashId,
            thumbUrl: _api.trashThumbUrl(trashId),
            http: _http,
            selected: selected,
            title: title,
            onTap: () {
              setState(() {
                if (selected) {
                  _selected.remove(trashId);
                } else {
                  _selected.add(trashId);
                }
              });
            },
          ),
        );
      },
    );
  }
}
