import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/io_client.dart';
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
import '../widgets/lazy_thumb_tile.dart';
import '../widgets/task_queue_panel.dart';
import 'trash_page.dart';

/// 手机相册浏览：照片/视频分栏、懒加载网格、预览、软删、重命名/归类、回收站入口
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
  /// 选中集合用 ValueNotifier，格子局部刷新，避免单击整页重建卡顿
  final _selection = ValueNotifier<Set<String>>(<String>{});
  final _scroll = ScrollController();
  final _albums = <Map<String, dynamic>>[];
  late final IOClient _http;

  int _page = 0;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _dragging = false;
  String? _error;
  bool _disconnectDialogShowing = false;
  String? _albumId;

  /// 与相册分类分开：照片 / 视频独立管理
  String _mediaType = MediaKind.image;

  bool get _isVideoMode => _mediaType == MediaKind.video;

  String get _deviceKey =>
      widget.device.deviceId.isNotEmpty
          ? widget.device.deviceId
          : '${widget.device.ip}:${widget.device.port}';

  @override
  void initState() {
    super.initState();
    _api = GalleryApiService(widget.device);
    _http = createPhotoLinkHttpClient();
    _queue = TransferTaskQueue(maxConcurrency: 2);
    _watchdog = ConnectionWatchdog(device: widget.device)..start();
    _watchdog.addListener(_onConnectionChanged);
    _scroll.addListener(_onScroll);
    ThumbnailCache.instance.purgeOlderThan();
    _bootstrap();
  }

  @override
  void dispose() {
    _watchdog.removeListener(_onConnectionChanged);
    _watchdog.dispose();
    _queue.dispose();
    _scroll.dispose();
    _selection.dispose();
    _http.close();
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
      await _reloadAlbums();
      await _loadPage(reset: true);
    } catch (e) {
      setState(() => _error = '连接失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadAlbums() async {
    try {
      final albums = await _api.listAlbums(mediaType: _mediaType);
      if (mounted) {
        setState(() {
          _albums
            ..clear()
            ..addAll(albums);
        });
      }
    } catch (_) {
      // 旧版手机端可能无 albums / mediaType，忽略即可
    }
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (reset) {
      _page = 0;
      _photos.clear();
      _selection.value = <String>{};
    }
    // 元数据分页加载；缩略图由格子组件自行懒加载，避免整页 setState 卡顿
    final result = await _api.listPhotos(
      page: _page,
      albumId: _albumId,
      mediaType: _mediaType,
    );
    if (!mounted) return;
    setState(() {
      _total = result.total;
      _photos.addAll(result.list);
    });
  }

  /// 切换照片 / 视频分栏时重置相册筛选并重载
  Future<void> _onMediaTypeChanged(String mediaType) async {
    final next = MediaKind.normalize(mediaType);
    if (next == _mediaType) return;
    setState(() {
      _mediaType = next;
      _albumId = null;
      _loading = true;
      _error = null;
    });
    try {
      await _reloadAlbums();
      await _loadPage(reset: true);
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    final next = Set<String>.from(_selection.value);
    if (!next.add(id)) next.remove(id);
    _selection.value = next;
  }

  /// 全选 / 取消全选（针对当前已加载列表）
  void _toggleSelectAll() {
    final allIds = _photos.map((e) => e.id).toSet();
    final allSelected =
        allIds.isNotEmpty && allIds.every(_selection.value.contains);
    _selection.value = allSelected ? <String>{} : allIds;
  }

  bool _allLoadedSelectedOf(Set<String> selected) {
    if (_photos.isEmpty) return false;
    return _photos.every((e) => selected.contains(e.id));
  }

  /// 主动断开：退出相册页并通知设备列表清除会话
  Future<void> _disconnectManually() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('断开连接'),
        content: const Text(
          '将断开与手机的当前会话并返回设备列表。\n'
          '请确认手机端保持亮屏且 App 在前台，以便稍后重新连接。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('断开'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop('disconnect');
    }
  }

  Future<void> _deleteSelected() async {
    if (_selection.value.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移入回收站'),
        content: Text(
          '将 ${_selection.value.length} 项${_isVideoMode ? '视频' : '照片'}移入回收站（可撤回）。'
          '彻底删除需在回收站中操作。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移入回收站'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      _toast('等待手机确认删除…');
      await _api.deletePhotos(_selection.value.toList());
      _toast('手机已确认，已移入回收站');
      await _loadPage(reset: true);
    } catch (e) {
      _toast('删除失败（手机拒绝/超时/网络）：$e');
    }
  }

  Future<void> _renameSelected() async {
    if (_selection.value.length != 1) {
      _toast('请先只选择一项再重命名');
      return;
    }
    final id = _selection.value.first;
    final current = _photos.firstWhere(
      (e) => e.id == id,
      orElse: () => PhotoMeta(
        id: id,
        width: 0,
        height: 0,
        createTimeMs: 0,
      ),
    );
    final controller = TextEditingController(text: current.title ?? '');
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '显示名称',
            hintText: '输入新名称',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    try {
      await _api.renamePhoto(id, title);
      _toast('已重命名');
      await _loadPage(reset: true);
    } catch (e) {
      _toast('重命名失败：$e');
    }
  }

  Future<void> _categorizeSelected() async {
    if (_selection.value.isEmpty) return;
    final controller = TextEditingController();
    final albumName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('归类到相册'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '将 ${_selection.value.length} 项${_isVideoMode ? '视频' : '图片'}'
              '归入手机相册分类（同步到系统相册）',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '相册名称',
                hintText: '例如：旅行 / 工作',
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            if (_albums.where((e) => e['isAll'] != true).isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _albums
                    .where((e) => e['isAll'] != true)
                    .take(8)
                    .map((e) {
                  final name = '${e['name'] ?? ''}';
                  return ActionChip(
                    label: Text(name),
                    onPressed: () => Navigator.pop(ctx, name),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('归类'),
          ),
        ],
      ),
    );
    if (albumName == null || albumName.isEmpty) return;
    try {
      await _api.categorizePhotos(
        photoIds: _selection.value.toList(),
        albumName: albumName,
      );
      _toast('已归类到「$albumName」');
      await _reloadAlbums();
      await _loadPage(reset: true);
    } catch (e) {
      _toast('归类失败：$e');
    }
  }

  Future<void> _openTrash() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrashPage(
          device: widget.device,
          deviceKey: _deviceKey,
        ),
      ),
    );
    if (mounted) await _loadPage(reset: true);
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
      name: photo.suggestedFileName,
      type: TransferTaskType.download,
      execute: ({required onProgress, required token}) async {
        final dir = await _ensureSaveDir();
        await _api.downloadOriginal(
          photoId: photo.id,
          saveDir: dir,
          fileName: photo.suggestedFileName,
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
    if (_selection.value.isEmpty) return;
    final selectedPhotos =
        _photos.where((e) => _selection.value.contains(e.id)).toList();
    for (final photo in selectedPhotos) {
      _enqueueDownload(photo);
    }
    _toast('已加入 ${selectedPhotos.length} 个下载任务');
  }

  static const _imageExts = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.heic',
    '.bmp',
  ];
  static const _videoExts = [
    '.mp4',
    '.mov',
    '.m4v',
    '.avi',
    '.mkv',
    '.webm',
    '.3gp',
    '.wmv',
  ];

  void _uploadFiles(List<XFile> files) {
    // 当前分栏只接收对应类型，避免图/视频混传造成错位
    final allow = _isVideoMode ? _videoExts : _imageExts;
    final matched = files.where((f) {
      final ext = p.extension(f.path).toLowerCase();
      return allow.contains(ext);
    }).toList();
    if (matched.isEmpty) {
      _toast(_isVideoMode ? '未检测到视频文件' : '未检测到图片文件');
      return;
    }
    final tasks = matched.map((x) {
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
      // 视频用 custom 扩展名；图片继续用系统图片选择器
      type: _isVideoMode ? FileType.custom : FileType.image,
      allowedExtensions: _isVideoMode
          ? _videoExts.map((e) => e.replaceFirst('.', '')).toList()
          : null,
    );
    if (result == null) return;
    final files = result.paths
        .whereType<String>()
        .map((path) => XFile(path))
        .toList();
    if (files.isNotEmpty) _uploadFiles(files);
  }

  Future<void> _onAlbumChanged(String? albumId) async {
    setState(() => _albumId = albumId);
    setState(() => _loading = true);
    try {
      await _loadPage(reset: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
              Text(
                '${widget.device.deviceName} · ${_isVideoMode ? '视频' : '相册'}',
              ),
              const SizedBox(width: 10),
              _ConnectionBadge(connected: connected),
            ],
          ),
          actions: [
            ValueListenableBuilder<Set<String>>(
              valueListenable: _selection,
              builder: (context, selected, _) {
                final allSelected = _allLoadedSelectedOf(selected);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_photos.isNotEmpty)
                      TextButton.icon(
                        onPressed: _toggleSelectAll,
                        icon: Icon(
                          allSelected
                              ? Icons.deselect_rounded
                              : Icons.select_all_rounded,
                        ),
                        label: Text(allSelected ? '取消全选' : '全选'),
                      ),
                    if (selected.isNotEmpty) ...[
                      TextButton.icon(
                        onPressed: _downloadSelected,
                        icon: const Icon(Icons.download_rounded),
                        label: Text('下载(${selected.length})'),
                      ),
                      TextButton.icon(
                        onPressed: _renameSelected,
                        icon: const Icon(
                          Icons.drive_file_rename_outline_rounded,
                        ),
                        label: const Text('重命名'),
                      ),
                      TextButton.icon(
                        onPressed: _categorizeSelected,
                        icon: const Icon(Icons.folder_special_rounded),
                        label: Text('归类(${selected.length})'),
                      ),
                      TextButton.icon(
                        onPressed: _deleteSelected,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text('移入回收站(${selected.length})'),
                      ),
                    ],
                  ],
                );
              },
            ),
            IconButton(
              tooltip: '打开回收站',
              onPressed: _openTrash,
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
            IconButton(
              tooltip: _isVideoMode ? '选择视频上传' : '选择图片上传',
              onPressed: _pickAndUpload,
              icon: const Icon(Icons.upload_file_rounded),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: () => _loadPage(reset: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: '断开连接',
              onPressed: _disconnectManually,
              icon: const Icon(Icons.link_off_rounded),
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
                  albums: _albums,
                  albumId: _albumId,
                  mediaType: _mediaType,
                  onAlbumChanged: _onAlbumChanged,
                  onMediaTypeChanged: _onMediaTypeChanged,
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
      return Center(
        child: Text(
          _isVideoMode
              ? '手机暂无视频\n可拖拽本地视频到此窗口上传，或点击右上角上传'
              : '手机相册暂无图片\n可拖拽本地图片到此窗口上传，或点击右上角上传',
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.5, color: Color(0xFF5A6F6D)),
        ),
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      cacheExtent: 280,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
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
        return RepaintBoundary(
          child: LazyThumbTile(
            key: ValueKey('${_mediaType}_${photo.id}'),
            cacheDeviceKey: _deviceKey,
            itemId: photo.id,
            thumbUrl: _api.thumbnailUrl(photo.id),
            http: _http,
            selection: _selection,
            isVideo: photo.isVideo,
            durationLabel: photo.isVideo
                ? _formatDuration(photo.durationMs)
                : null,
            onTap: () => _toggleSelect(photo.id),
            onSecondaryTap: () => _showPhotoMenu(photo),
            badge: (photo.albumName != null && photo.albumName!.isNotEmpty)
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      photo.albumName!,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  )
                : null,
            bottomLeft: IconButton(
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(4),
                minimumSize: const Size(32, 32),
              ),
              tooltip: photo.isVideo ? '下载视频' : '下载原图',
              onPressed: () => _enqueueDownload(photo),
              icon: const Icon(Icons.download_rounded, size: 18),
            ),
          ),
        );
      },
    );
  }

  /// 将毫秒时长格式化为 m:ss / h:mm:ss
  String _formatDuration(int ms) {
    if (ms <= 0) return '视频';
    final totalSec = (ms / 1000).round();
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _showPhotoMenu(PhotoMeta photo) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                _isVideoMode
                    ? Icons.play_circle_outline_rounded
                    : Icons.zoom_in_rounded,
              ),
              title: Text(_isVideoMode ? '预览视频' : '预览原图'),
              onTap: () => Navigator.pop(ctx, 'preview'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('重命名'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_special_rounded),
              title: const Text('归类'),
              onTap: () => Navigator.pop(ctx, 'categorize'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('移入回收站'),
              onTap: () => Navigator.pop(ctx, 'trash'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    // 赋新 Set 才能触发 ValueNotifier，原地 clear/add 不会通知格子
    _selection.value = {photo.id};
    switch (action) {
      case 'preview':
        await _preview(photo);
        break;
      case 'rename':
        await _renameSelected();
        break;
      case 'categorize':
        await _categorizeSelected();
        break;
      case 'trash':
        await _deleteSelected();
        break;
    }
  }

  /// 图片：原图像素预览；视频：缓存到临时目录后用系统播放器打开
  Future<void> _preview(PhotoMeta photo) async {
    if (photo.isVideo) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => _VideoPreviewDialog(
          title: photo.title ?? photo.id,
          durationLabel: _formatDuration(photo.durationMs),
          downloadToTemp: () async {
            final tmp = await getTemporaryDirectory();
            final dir = Directory(p.join(tmp.path, 'photolink_preview'));
            return _api.downloadOriginal(
              photoId: photo.id,
              saveDir: dir,
              fileName: photo.suggestedFileName,
            );
          },
          onDownload: () {
            Navigator.pop(ctx);
            _enqueueDownload(photo);
          },
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => _OriginalPreviewDialog(
        title: photo.title ?? photo.id,
        loadBytes: () => _api.fetchOriginalBytes(photo.id),
        onDownload: () {
          Navigator.pop(ctx);
          _enqueueDownload(photo);
        },
      ),
    );
  }
}

/// 独立 StatefulWidget，避免在 build 里反复触发原图请求
class _OriginalPreviewDialog extends StatefulWidget {
  const _OriginalPreviewDialog({
    required this.title,
    required this.loadBytes,
    required this.onDownload,
  });

  final String title;
  final Future<Uint8List> Function() loadBytes;
  final VoidCallback onDownload;

  @override
  State<_OriginalPreviewDialog> createState() => _OriginalPreviewDialogState();
}

class _OriginalPreviewDialogState extends State<_OriginalPreviewDialog> {
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.loadBytes();
      if (!mounted) return;
      setState(() {
        _bytes = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 860),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(widget.title),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  tooltip: '下载',
                  onPressed: widget.onDownload,
                  icon: const Icon(Icons.download_rounded),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(48),
                      child: CircularProgressIndicator(),
                    )
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('预览失败：$_error'),
                        )
                      : InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 5,
                          child: Image.memory(_bytes!),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 连接状态小徽章（相册页标题旁）
class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final color =
        connected ? const Color(0xFF1FA87A) : Colors.red.shade700;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: connected
            ? const Color(0xFF1FA87A).withValues(alpha: 0.15)
            : Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            connected
                ? Icons.wifi_tethering_rounded
                : Icons.wifi_tethering_error_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            connected ? '设备已连接' : '连接已断开',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
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
    required this.albums,
    required this.albumId,
    required this.mediaType,
    required this.onAlbumChanged,
    required this.onMediaTypeChanged,
  });

  final DeviceInfoModel device;
  final int total;
  final int loaded;
  final bool connected;
  final List<Map<String, dynamic>> albums;
  final String? albumId;
  final String mediaType;
  final ValueChanged<String?> onAlbumChanged;
  final ValueChanged<String> onMediaTypeChanged;

  @override
  Widget build(BuildContext context) {
    final isVideo = mediaType == MediaKind.video;
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
            // 照片 / 视频分栏，与系统相册筛选相互独立
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: MediaKind.image,
                  label: Text('照片'),
                  icon: Icon(Icons.photo_rounded, size: 18),
                ),
                ButtonSegment<String>(
                  value: MediaKind.video,
                  label: Text('视频'),
                  icon: Icon(Icons.videocam_rounded, size: 18),
                ),
              ],
              selected: {mediaType},
              onSelectionChanged: (set) {
                if (set.isNotEmpty) onMediaTypeChanged(set.first);
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return PhotoLinkTheme.brand.withValues(alpha: 0.15);
                  }
                  return Colors.white;
                }),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '已加载 $loaded / $total · ${isVideo ? '视频' : '照片'} · 最近在前',
            ),
            if (albums.isNotEmpty) ...[
              const SizedBox(width: 16),
              AlbumPickerButton(
                albums: albums,
                albumId: albumId,
                onChanged: onAlbumChanged,
              ),
            ],
            const Spacer(),
            // 右侧醒目展示链路连通状态
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  connected
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  size: 16,
                  color: connected
                      ? const Color(0xFF1FA87A)
                      : Colors.red.shade700,
                ),
                const SizedBox(width: 6),
                Text(
                  connected
                      ? '请保持手机亮屏 · 单击选择 · 右键预览 · 拖拽上传'
                      : '连接已断开，传输可能失败',
                  style: TextStyle(
                    color: connected
                        ? const Color(0xFF5A6F6D)
                        : Colors.red.shade700,
                    fontWeight:
                        connected ? FontWeight.w500 : FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 视频预览：先下载到临时目录，再用系统默认播放器打开（避免自签 HTTPS 直链播放）
class _VideoPreviewDialog extends StatefulWidget {
  const _VideoPreviewDialog({
    required this.title,
    required this.durationLabel,
    required this.downloadToTemp,
    required this.onDownload,
  });

  final String title;
  final String durationLabel;
  final Future<File> Function() downloadToTemp;
  final VoidCallback onDownload;

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  bool _loading = false;
  String? _error;
  String? _localPath;

  Future<void> _play() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final file = await widget.downloadToTemp();
      if (!mounted) return;
      setState(() {
        _localPath = file.path;
        _loading = false;
      });
      await _openWithSystemPlayer(file.path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// Windows / macOS / Linux 用系统默认应用打开本地文件
  Future<void> _openWithSystemPlayer(String path) async {
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', path]);
      return;
    }
    if (Platform.isMacOS) {
      await Process.start('open', [path]);
      return;
    }
    await Process.start('xdg-open', [path]);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(widget.title),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  tooltip: '下载到电脑',
                  onPressed: widget.onDownload,
                  icon: const Icon(Icons.download_rounded),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                children: [
                  const Icon(
                    Icons.videocam_rounded,
                    size: 56,
                    color: PhotoLinkTheme.brand,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '时长 ${widget.durationLabel}',
                    style: const TextStyle(
                      color: Color(0xFF5A6F6D),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _localPath == null
                        ? '将缓存到临时目录后用系统播放器打开'
                        : '已缓存：$_localPath',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF5A6F6D),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '打开失败：$_error',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _loading ? null : _play,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(_loading ? '准备中…' : '用系统播放器打开'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
