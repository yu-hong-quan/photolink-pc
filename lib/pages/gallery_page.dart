import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/models/device_info.dart';
import '../core/models/photo_meta.dart';
import '../services/api_client.dart';
import '../services/connection_watchdog.dart';
import '../services/gallery_api_service.dart';
import '../services/thumbnail_cache.dart';
import '../services/transfer_task_queue.dart';
import '../theme/app_theme.dart';
import '../widgets/task_queue_panel.dart';

/// 手机相册浏览：网格、多选删除、批量下载、拖拽上传、任务队列
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key, required this.device});

  final DeviceInfoModel device;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  late final GalleryApiService _api;
  late final TransferTaskQueue _queue;
  late final ConnectionWatchdog _watchdog;

  final _photos = <PhotoMeta>[];
  final _selected = <String>{};
  final _thumbCache = <String, Uint8List>{};
  final _scroll = ScrollController();

  int _page = 0;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _dragging = false;
  String? _error;
  bool _disconnectDialogShowing = false;

  String get _deviceKey =>
      widget.device.deviceId.isNotEmpty
          ? widget.device.deviceId
          : '${widget.device.ip}:${widget.device.port}';

  @override
  void initState() {
    super.initState();
    _api = GalleryApiService(widget.device);
    _queue = TransferTaskQueue(maxConcurrency: 2);
    _watchdog = ConnectionWatchdog(device: widget.device)..start();
    _watchdog.addListener(_onConnectionChanged);
    _scroll.addListener(_onScroll);
    // 后台清理过期缩略图缓存
    ThumbnailCache.instance.purgeOlderThan();
    _bootstrap();
  }

  @override
  void dispose() {
    _watchdog.removeListener(_onConnectionChanged);
    _watchdog.dispose();
    _queue.dispose();
    _scroll.dispose();
    _api.close();
    super.dispose();
  }

  void _onConnectionChanged() {
    if (!mounted) return;
    setState(() {});
    if (!_watchdog.isConnected) {
      _showDisconnectDialog();
    }
  }

  Future<void> _showDisconnectDialog() async {
    if (_disconnectDialogShowing || !mounted) return;
    _disconnectDialogShowing = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('设备已断开'),
        content: Text(
          '与手机的连接似乎已中断。\n${_watchdog.lastError ?? ''}\n\n'
          '请确认手机 App 在前台、同一 WiFi，然后重试。',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).maybePop();
            },
            child: const Text('返回设备列表'),
          ),
          FilledButton(
            onPressed: () async {
              final ok = await _watchdog.probeNow();
              if (!ctx.mounted) return;
              if (ok) {
                Navigator.pop(ctx);
                _toast('已重新连接');
                await _loadPage(reset: true);
              } else {
                _toast('仍无法连接，请检查手机端');
              }
            },
            child: const Text('重试连接'),
          ),
        ],
      ),
    );
    _disconnectDialogShowing = false;
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.fetchDeviceInfo();
      await _loadPage(reset: true);
    } catch (e) {
      setState(() => _error = '连接失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (reset) {
      _page = 0;
      _photos.clear();
      _selected.clear();
    }
    final result = await _api.listPhotos(page: _page);
    if (!mounted) return;
    setState(() {
      _total = result.total;
      _photos.addAll(result.list);
    });
    for (final photo in result.list) {
      _prefetchThumb(photo.id);
    }
  }

  Future<void> _prefetchThumb(String id) async {
    if (_thumbCache.containsKey(id)) return;
    // 先读本地磁盘缓存
    final cached = await ThumbnailCache.instance.get(_deviceKey, id);
    if (cached != null && mounted) {
      setState(() => _thumbCache[id] = cached);
      return;
    }
    try {
      final client = createPhotoLinkHttpClient();
      final res = await client.get(Uri.parse(_api.thumbnailUrl(id)));
      client.close();
      if (res.statusCode == 200 && mounted) {
        final bytes = res.bodyBytes;
        await ThumbnailCache.instance.put(_deviceKey, id, bytes);
        if (mounted) setState(() => _thumbCache[id] = bytes);
      }
    } catch (_) {}
  }

  void _onScroll() {
    if (_loadingMore || _photos.length >= _total) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      _page += 1;
      await _loadPage();
    } catch (e) {
      _page -= 1;
      _toast('加载更多失败：$e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
          '将从手机相册删除 ${_selected.length} 张照片，此操作不可恢复。是否继续？',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deletePhotos(_selected.toList());
      _toast('删除成功');
      await _loadPage(reset: true);
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  Directory? _saveDir;

  Future<Directory> _ensureSaveDir() async {
    if (_saveDir != null) return _saveDir!;
    final docs =
        await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    _saveDir = Directory(p.join(docs.path, 'PhotoLink'));
    return _saveDir!;
  }

  void _enqueueDownload(PhotoMeta photo) {
    final task = TransferTask(
      id: 'dl_${photo.id}_${const Uuid().v4()}',
      name: photo.title?.isNotEmpty == true ? photo.title! : 'photo_${photo.id}',
      type: TransferTaskType.download,
      execute: ({required onProgress, required token}) async {
        final dir = await _ensureSaveDir();
        await _api.downloadOriginal(
          photoId: photo.id,
          saveDir: dir,
          fileName: '${photo.id}.jpg',
          token: token,
          onProgress: (received, total) {
            final progress =
                total == null || total <= 0 ? 0.0 : received / total;
            onProgress(progress, received, total);
          },
        );
      },
    );
    _queue.enqueue(task);
  }

  void _downloadSelected() {
    if (_selected.isEmpty) return;
    final selectedPhotos =
        _photos.where((e) => _selected.contains(e.id)).toList();
    for (final photo in selectedPhotos) {
      _enqueueDownload(photo);
    }
    _toast('已加入 ${selectedPhotos.length} 个下载任务');
  }

  void _uploadFiles(List<XFile> files) {
    final images = files.where((f) {
      final ext = p.extension(f.path).toLowerCase();
      return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.bmp']
          .contains(ext);
    }).toList();
    if (images.isEmpty) {
      _toast('未检测到图片文件');
      return;
    }
    final tasks = images.map((x) {
      return TransferTask(
        id: 'up_${const Uuid().v4()}',
        name: p.basename(x.path),
        type: TransferTaskType.upload,
        execute: ({required onProgress, required token}) async {
          await _api.uploadFile(
            File(x.path),
            token: token,
            onProgress: (sent, total) {
              onProgress(total == 0 ? 0 : sent / total, sent, total);
            },
          );
        },
      );
    }).toList();
    _queue.enqueueAll(tasks);
    _toast('已加入 ${tasks.length} 个上传任务');
    // 上传完成后刷新列表：监听队列
    _watchUploadsThenRefresh(tasks.map((e) => e.id).toSet());
  }

  void _watchUploadsThenRefresh(Set<String> ids) {
    void listener() {
      final related = _queue.tasks.where((t) => ids.contains(t.id));
      if (related.isEmpty) return;
      final allDone = related.every(
        (t) =>
            t.status == TransferTaskStatus.success ||
            t.status == TransferTaskStatus.failed ||
            t.status == TransferTaskStatus.cancelled,
      );
      if (allDone) {
        _queue.removeListener(listener);
        final anySuccess =
            related.any((t) => t.status == TransferTaskStatus.success);
        if (anySuccess && mounted) {
          _loadPage(reset: true);
        }
      }
    }

    _queue.addListener(listener);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );
    if (result == null) return;
    final files = result.paths
        .whereType<String>()
        .map((path) => XFile(path))
        .toList();
    if (files.isNotEmpty) _uploadFiles(files);
  }

  @override
  Widget build(BuildContext context) {
    final connected = _watchdog.isConnected;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) async {
        setState(() => _dragging = false);
        _uploadFiles(detail.files);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F7F6),
        appBar: AppBar(
          title: Row(
            children: [
              Text('${widget.device.deviceName} 相册'),
              const SizedBox(width: 10),
              _ConnectionBadge(connected: connected),
            ],
          ),
          actions: [
            if (_selected.isNotEmpty) ...[
              TextButton.icon(
                onPressed: _downloadSelected,
                icon: const Icon(Icons.download_rounded),
                label: Text('下载(${_selected.length})'),
              ),
              TextButton.icon(
                onPressed: _deleteSelected,
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text('删除(${_selected.length})'),
              ),
            ],
            IconButton(
              tooltip: '选择图片上传',
              onPressed: _pickAndUpload,
              icon: const Icon(Icons.upload_file_rounded),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: () => _loadPage(reset: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                _HeaderBar(
                  device: widget.device,
                  total: _total,
                  loaded: _photos.length,
                  connected: connected,
                ),
                Expanded(child: _buildBody()),
                TaskQueuePanel(queue: _queue),
              ],
            ),
            IgnorePointer(
              ignoring: !_dragging,
              child: AnimatedOpacity(
                opacity: _dragging ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  color: PhotoLinkTheme.brand.withValues(alpha: 0.18),
                  alignment: Alignment.center,
                  child: AnimatedScale(
                    scale: _dragging ? 1 : 0.92,
                    duration: const Duration(milliseconds: 180),
                    child: const Card(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 22,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_upload_rounded,
                                color: PhotoLinkTheme.brand, size: 28),
                            SizedBox(width: 12),
                            Text(
                              '松开鼠标，加入上传队列',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
            FilledButton(onPressed: _bootstrap, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_photos.isEmpty) {
      return const Center(
        child: Text(
          '手机相册暂无图片\n可拖拽本地图片到此窗口上传，或点击右上角上传',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.5, color: Color(0xFF5A6F6D)),
        ),
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: _photos.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _photos.length) {
          return const Center(child: CircularProgressIndicator());
        }
        final photo = _photos[index];
        final selected = _selected.contains(photo.id);
        final bytes = _thumbCache[photo.id];
        return AnimatedScale(
          scale: selected ? 0.96 : 1,
          duration: const Duration(milliseconds: 160),
          child: Material(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _toggleSelect(photo.id),
              onDoubleTap: () => _preview(photo),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  bytes == null
                      ? const Center(child: Icon(Icons.image_outlined))
                      : Image.memory(bytes, fit: BoxFit.cover),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: selected
                            ? PhotoLinkTheme.brand
                            : Colors.transparent,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: selected ? PhotoLinkTheme.brand : Colors.white,
                    ),
                  ),
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(4),
                        minimumSize: const Size(32, 32),
                      ),
                      tooltip: '下载原图',
                      onPressed: () => _enqueueDownload(photo),
                      icon: const Icon(Icons.download_rounded, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _preview(PhotoMeta photo) async {
    final bytes = _thumbCache[photo.id];
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: Text(photo.title ?? photo.id),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _enqueueDownload(photo);
                    },
                    icon: const Icon(Icons.download_rounded),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Flexible(
                child: bytes == null
                    ? const Padding(
                        padding: EdgeInsets.all(48),
                        child: CircularProgressIndicator(),
                      )
                    : InteractiveViewer(child: Image.memory(bytes)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 连接状态小徽章
class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: connected
            ? const Color(0xFF1FA87A).withValues(alpha: 0.15)
            : Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        connected ? '已连接' : '已断开',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: connected ? const Color(0xFF1FA87A) : Colors.red.shade700,
        ),
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.device,
    required this.total,
    required this.loaded,
    required this.connected,
  });

  final DeviceInfoModel device;
  final int total;
  final int loaded;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE8F4F2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${device.ip}:${device.port}'),
            ),
            const SizedBox(width: 12),
            Text('已加载 $loaded / $total'),
            const Spacer(),
            Text(
              connected
                  ? '单击选择 · 双击预览 · 拖拽/按钮上传 · 批量下载'
                  : '连接已断开，传输可能失败',
              style: TextStyle(
                color: connected ? const Color(0xFF5A6F6D) : Colors.red.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
