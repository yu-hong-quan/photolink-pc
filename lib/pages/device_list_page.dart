import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/constants.dart';
import '../core/models/device_info.dart';
import '../services/device_history_store.dart';
import '../services/gallery_api_service.dart';
import '../services/mdns_discovery_service.dart';
import '../services/pc_pair_service.dart';
import '../theme/app_theme.dart';
import '../widgets/motion.dart';
import 'gallery_page.dart';

/// PC 设备列表：实时可连接设备 + 历史连接记录
class DeviceListPage extends StatefulWidget {
  const DeviceListPage({super.key});

  @override
  State<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends State<DeviceListPage> {
  final _discovery = MdnsDiscoveryService();
  final _pairService = PcPairService();
  StreamSubscription<List<DeviceInfoModel>>? _sub;
  StreamSubscription<DeviceInfoModel>? _pairSub;

  /// 当前局域网实时可见（mDNS / 刚扫码配对）
  final _liveDevices = <String, DeviceInfoModel>{};
  /// 扫码/手动刚加入的实时设备，短时保活（避免 mDNS 尚未广播就被冲掉）
  final _stickyLiveUntil = <String, DateTime>{};
  /// 本地持久化的连接记录
  List<DeviceHistoryEntry> _history = [];

  DeviceInfoModel? _pcInfo;
  bool _scanning = true;
  String? _scanError;
  String? _pairError;
  final _autoRescanTimers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    for (final t in _autoRescanTimers) {
      t.cancel();
    }
    _autoRescanTimers.clear();
    _sub?.cancel();
    _pairSub?.cancel();
    _discovery.dispose();
    _pairService.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _history = await DeviceHistoryStore.instance.load();
    if (mounted) setState(() {});

    // 订阅一次即可；后续只 restart discovery，避免反复 cancel 丢事件
    _sub?.cancel();
    _sub = _discovery.devicesStream.listen((list) {
      if (!mounted) return;
      _applyLiveList(list);
    });

    // 等首帧 + 短延迟：避开窗口/托盘初始化抢网卡导致的首次 mDNS 空跑
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    await Future.wait([
      _startPairServer(),
      _startScan(isManual: false, preserveCache: false),
      _probeHistoryOnline(),
    ]);

    // Windows Bonsoir 常需 2～3 次启动才稳定出结果；无设备时多轮自动重扫
    _scheduleAutoRescans();
  }

  /// 在 1.2s / 3s / 5.5s 自动重启发现（已有实时设备则跳过）
  void _scheduleAutoRescans() {
    for (final t in _autoRescanTimers) {
      t.cancel();
    }
    _autoRescanTimers.clear();
    for (final ms in [1200, 3000, 5500]) {
      _autoRescanTimers.add(Timer(Duration(milliseconds: ms), () {
        if (!mounted) return;
        if (_liveDevices.isNotEmpty) return;
        _startScan(isManual: false, preserveCache: true);
      }));
    }
  }

  Future<void> _startPairServer() async {
    try {
      final info = await _pairService.start();
      _pairSub?.cancel();
      _pairSub = _pairService.pairedPhoneStream.listen((phone) async {
        if (!mounted) return;
        _upsertLive(phone);
        // 扫码配对即记入历史，便于下次快速找到
        _history = await DeviceHistoryStore.instance.upsert(phone);
        if (!mounted) return;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('手机「${phone.deviceName}」已扫码配对（${phone.ip}:${phone.port}）'),
            action: SnackBarAction(
              label: '立即连接',
              onPressed: () => _connect(phone),
            ),
          ),
        );
      });
      if (mounted) {
        setState(() {
          _pcInfo = info;
          _pairError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() =>
            _pairError = '配对服务启动失败：$e（端口 ${PhotoLinkConst.pairPort}）');
      }
    }
  }

  /// 用户点刷新：只重扫列表，不打断相册页已有 HTTPS 会话；保留实时项
  Future<void> _refreshDeviceList() async {
    // 延长 sticky，避免 mDNS 瞬时空结果把「可连接」项冲掉
    final stickyUntil = DateTime.now().add(const Duration(minutes: 5));
    for (final key in _liveDevices.keys) {
      _stickyLiveUntil[key] = stickyUntil;
    }
    await Future.wait([
      _startScan(isManual: true, preserveCache: true),
      _probeHistoryOnline(),
    ]);
  }

  Future<void> _startScan({
    bool isManual = true,
    bool preserveCache = true,
  }) async {
    if (!mounted) return;
    setState(() {
      _scanning = true;
      _scanError = null;
    });
    try {
      // preserveCache=true 时不刷空已发现设备（含相册页底层列表）
      await _discovery.start(preserveCache: preserveCache);
      if (mounted) _applyLiveList(_discovery.devices);
    } catch (e) {
      if (mounted) setState(() => _scanError = 'mDNS 启动失败：$e');
    } finally {
      // 手动刷新稍候关「扫描中」；自动扫描多留一会方便多轮重试
      final delay = isManual
          ? const Duration(milliseconds: 800)
          : const Duration(milliseconds: 2800);
      Future<void>.delayed(delay, () {
        if (mounted) setState(() => _scanning = false);
      });
    }
  }

  void _applyLiveList(List<DeviceInfoModel> list) {
    final now = DateTime.now();
    final next = <String, DeviceInfoModel>{};
    for (final d in list) {
      next[_keyOf(d)] = d;
    }
    // 刚扫码/手动加入的设备短时保留在「实时」区
    _stickyLiveUntil.removeWhere((_, until) => until.isBefore(now));
    for (final key in _stickyLiveUntil.keys) {
      final cached = _liveDevices[key];
      if (cached != null) next.putIfAbsent(key, () => cached);
    }
    setState(() {
      _liveDevices
        ..clear()
        ..addAll(next);
    });
  }

  /// 启动时探测历史设备是否仍在线，不依赖 mDNS 也能进「实时可连接」
  Future<void> _probeHistoryOnline() async {
    if (_history.isEmpty) return;
    await Future.wait(_history.map((entry) async {
      final api = GalleryApiService(entry.device);
      try {
        final remote = await api
            .fetchDeviceInfo()
            .timeout(const Duration(seconds: 2));
        if (!mounted) return;
        final merged = DeviceInfoModel(
          deviceId:
              remote.deviceId.isNotEmpty ? remote.deviceId : entry.device.deviceId,
          deviceName: remote.deviceName.isNotEmpty
              ? remote.deviceName
              : entry.device.deviceName,
          deviceType: remote.deviceType,
          osVersion: remote.osVersion,
          ip: entry.device.ip,
          port: entry.device.port,
        );
        _upsertLive(merged);
      } catch (_) {
        // 离线忽略
      } finally {
        api.close();
      }
    }));
  }

  String _keyOf(DeviceInfoModel device) => DeviceHistoryStore.keyOf(device);

  void _upsertLive(DeviceInfoModel device, {bool notify = true}) {
    final key = _keyOf(device);
    _liveDevices[key] = device;
    _stickyLiveUntil[key] = DateTime.now().add(const Duration(minutes: 5));
    if (notify && mounted) setState(() {});
  }

  /// 实时列表：当前在线/刚配对
  List<DeviceInfoModel> get _liveList => _liveDevices.values.toList();

  /// 历史中不在实时列表里的记录（离线记录）
  List<DeviceHistoryEntry> get _historyOnly {
    final liveKeys = _liveDevices.keys.toSet();
    return _history
        .where((e) => !liveKeys.contains(_keyOf(e.device)))
        .toList();
  }

  Future<void> _removeHistory(DeviceHistoryEntry entry) async {
    _history = await DeviceHistoryStore.instance.remove(_keyOf(entry.device));
    if (mounted) setState(() {});
  }

  Future<void> _connect(DeviceInfoModel device) async {
    final api = GalleryApiService(device);
    try {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      final remote = await api.fetchDeviceInfo();
      if (!mounted) return;
      Navigator.of(context).pop();
      final merged = DeviceInfoModel(
        deviceId: remote.deviceId.isNotEmpty ? remote.deviceId : device.deviceId,
        deviceName:
            remote.deviceName.isNotEmpty ? remote.deviceName : device.deviceName,
        deviceType: remote.deviceType,
        osVersion: remote.osVersion,
        ip: device.ip,
        port: device.port,
      );
      // 连接成功：写入实时 + 历史记录
      _upsertLive(merged);
      _history = await DeviceHistoryStore.instance.upsert(merged);
      if (!mounted) return;
      setState(() {});

      await Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              GalleryPage(device: merged),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.04, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                )),
                child: child,
              ),
            );
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '连接失败：$e\n请确认手机 App 在前台，且防火墙放行 ${device.ip}:${device.port}',
            ),
          ),
        );
      }
    } finally {
      api.close();
    }
  }

  Future<void> _showManualConnect() async {
    final ipCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '${PhotoLinkConst.port}');
    final payloadCtrl = TextEditingController();

    final device = await showDialog<DeviceInfoModel>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('手动连接'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: payloadCtrl,
                  decoration: const InputDecoration(
                    labelText: '手机连接串（可选）',
                    hintText: 'photolink://192.168.x.x:53317?...',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ipCtrl,
                  decoration: const InputDecoration(labelText: '手机 IP'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: portCtrl,
                  decoration: const InputDecoration(labelText: '端口'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final fromPayload =
                    DeviceInfoModel.fromConnectPayload(payloadCtrl.text);
                if (fromPayload != null) {
                  Navigator.pop(ctx, fromPayload);
                  return;
                }
                final ip = ipCtrl.text.trim();
                final port = int.tryParse(portCtrl.text.trim()) ??
                    PhotoLinkConst.port;
                if (ip.isEmpty) return;
                Navigator.pop(
                  ctx,
                  DeviceInfoModel(
                    deviceId: '$ip:$port',
                    deviceName: '手动设备',
                    deviceType: 'phone',
                    osVersion: '',
                    ip: ip,
                    port: port,
                  ),
                );
              },
              child: const Text('连接'),
            ),
          ],
        );
      },
    );

    if (device != null) {
      _upsertLive(device);
      await _connect(device);
    }
  }

  Future<void> _showQrDialog() async {
    final info = _pcInfo;
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_pairError ?? '配对服务未就绪')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('扫码连接（请用手机 App 扫）'),
        content: SizedBox(
          width: 340,
          child: _PcQrPanel(pcInfo: info, large: true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pc = _pcInfo;
    return SoftGradientBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [PhotoLinkTheme.brand, PhotoLinkTheme.brandDark],
                  ),
                ),
                child: const Icon(Icons.link_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('${PhotoLinkConst.appName} · ${PhotoLinkConst.appNameZh}'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '刷新设备列表（不中断已连接相册）',
              onPressed: _refreshDeviceList,
              icon: const Icon(Icons.refresh_rounded),
            ),
            FilledButton.tonalIcon(
              onPressed: _showQrDialog,
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('放大二维码'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _showManualConnect,
              icon: const Icon(Icons.edit_rounded),
              label: const Text('手动连接'),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: Row(
          children: [
            FadeSlideIn(
              child: SizedBox(
                width: 340,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 420),
                        child: pc == null
                            ? Center(
                                key: const ValueKey('loading'),
                                child: Text(
                                  _pairError ?? '正在生成配对二维码…',
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : _PcQrPanel(
                                key: const ValueKey('qr'),
                                pcInfo: pc,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: FadeSlideIn(
                delay: const Duration(milliseconds: 120),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                PhotoLinkTheme.brand.withValues(alpha: 0.12),
                                PhotoLinkTheme.accent.withValues(alpha: 0.08),
                              ],
                            ),
                          ),
                          child: Row(
                            children: [
                              PulseDot(
                                color: _scanning
                                    ? PhotoLinkTheme.accent
                                    : PhotoLinkTheme.brand,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '设备列表',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '实时可连接 ${_liveList.length} · 历史记录 ${_history.length}',
                                      style: const TextStyle(
                                        color: Color(0xFF5A6F6D),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              AnimatedOpacity(
                                opacity: _scanning ? 1 : 0.35,
                                duration: const Duration(milliseconds: 300),
                                child: const Text(
                                  '扫描中',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF5A6F6D),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_scanError != null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _scanError!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        Expanded(child: _buildDeviceBody()),
                      ],
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

  Widget _buildDeviceBody() {
    final live = _liveList;
    final historyOnly = _historyOnly;
    if (live.isEmpty && historyOnly.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.phonelink_setup_rounded,
              size: 64,
              color: PhotoLinkTheme.brand.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            const Text(
              '暂无实时设备与连接记录',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '请打开手机 PhotoLink → 点「扫描电脑二维码」',
              style: TextStyle(color: Color(0xFF5A6F6D)),
            ),
            if (_scanning) ...[
              const SizedBox(height: 20),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ],
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle(
          title: '实时可连接',
          subtitle: live.isEmpty ? '当前未发现在线手机' : 'mDNS 发现或刚扫码配对',
          badge: live.length,
          online: true,
        ),
        const SizedBox(height: 10),
        if (live.isEmpty)
          const _EmptyHint(text: '等待手机扫码或局域网自动发现…')
        else
          ...List.generate(live.length, (index) {
            final d = live[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DeviceTile(
                device: d,
                live: true,
                onConnect: () => _connect(d),
              ),
            );
          }),
        const SizedBox(height: 18),
        _SectionTitle(
          title: '连接记录',
          subtitle: historyOnly.isEmpty
              ? (_history.isEmpty ? '连接成功后会自动保存' : '记录中的设备均在线，见上方')
              : '曾连接过，当前未在实时列表中',
          badge: _history.length,
          online: false,
        ),
        const SizedBox(height: 10),
        if (historyOnly.isEmpty)
          _EmptyHint(
            text: _history.isEmpty ? '暂无历史记录' : '历史设备均已出现在「实时可连接」',
          )
        else
          ...List.generate(historyOnly.length, (index) {
            final entry = historyOnly[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DeviceTile(
                device: entry.device,
                live: false,
                lastConnectedAtMs: entry.lastConnectedAtMs,
                onConnect: () => _connect(entry.device),
                onRemove: () => _removeHistory(entry),
              ),
            );
          }),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.online,
  });

  final String title;
  final String subtitle;
  final int badge;
  final bool online;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: online ? const Color(0xFF1FA87A) : const Color(0xFF9AABA8),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: online
                ? const Color(0xFF1FA87A).withValues(alpha: 0.12)
                : Colors.black12,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('$badge', style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF8A9C9A), fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text, style: const TextStyle(color: Color(0xFF5A6F6D))),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.live,
    required this.onConnect,
    this.lastConnectedAtMs,
    this.onRemove,
  });

  final DeviceInfoModel device;
  final bool live;
  final VoidCallback onConnect;
  final int? lastConnectedAtMs;
  final VoidCallback? onRemove;

  String? get _timeHint {
    final ms = lastConnectedAtMs;
    if (ms == null || ms <= 0) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '上次连接 ${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: live ? const Color(0xFFF8FBFA) : const Color(0xFFF5F5F5),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onConnect,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: (live ? PhotoLinkTheme.brand : Colors.grey)
                      .withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.phone_android_rounded,
                  color: live ? PhotoLinkTheme.brand : Colors.grey,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            device.deviceName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: live
                                ? const Color(0xFF1FA87A).withValues(alpha: 0.15)
                                : Colors.black12,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            live ? '在线' : '离线记录',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: live
                                  ? const Color(0xFF1FA87A)
                                  : const Color(0xFF6A7A78),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${device.ip}:${device.port}',
                      style: const TextStyle(color: Color(0xFF5A6F6D)),
                    ),
                    if (_timeHint != null)
                      Text(
                        _timeHint!,
                        style: const TextStyle(
                          color: Color(0xFF8A9C9A),
                          fontSize: 12,
                        ),
                      )
                    else if (device.osVersion.isNotEmpty)
                      Text(
                        device.osVersion,
                        style: const TextStyle(
                          color: Color(0xFF8A9C9A),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: '删除记录',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              FilledButton(
                onPressed: onConnect,
                child: Text(live ? '连接' : '重连'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PcQrPanel extends StatelessWidget {
  const _PcQrPanel({super.key, required this.pcInfo, this.large = false});

  final DeviceInfoModel pcInfo;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final payload = pcInfo.toPcPairPayload();
    final size = large ? 260.0 : 196.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          '扫码连接',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          '请用手机 App 扫描此二维码',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF5A6F6D)),
        ),
        const SizedBox(height: 18),
        BreathingBorder(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(10),
            child: QrImageView(
              data: payload,
              size: size,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: PhotoLinkTheme.brandDark,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: PhotoLinkTheme.brandDark,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: PhotoLinkTheme.brand.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${pcInfo.ip}  ·  端口 ${pcInfo.port}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        // 配对链接：可选中，并提供一键复制
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF7FAF9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: PhotoLinkTheme.brand.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  payload,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF5A6F6D),
                    height: 1.35,
                  ),
                ),
              ),
              IconButton(
                tooltip: '复制链接',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: payload));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('配对链接已复制')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
