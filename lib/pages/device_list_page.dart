import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/constants.dart';
import '../core/models/device_info.dart';
import '../services/gallery_api_service.dart';
import '../services/mdns_discovery_service.dart';
import '../services/pc_pair_service.dart';
import '../theme/app_theme.dart';
import '../widgets/motion.dart';
import 'gallery_page.dart';

/// PC 设备列表：配对二维码 + 自动发现 + 手动连接
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
  final _devices = <String, DeviceInfoModel>{};
  DeviceInfoModel? _pcInfo;
  bool _scanning = true;
  String? _scanError;
  String? _pairError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pairSub?.cancel();
    _discovery.dispose();
    _pairService.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_startPairServer(), _startScan()]);
  }

  Future<void> _startPairServer() async {
    try {
      final info = await _pairService.start();
      _pairSub?.cancel();
      _pairSub = _pairService.pairedPhoneStream.listen((phone) {
        if (!mounted) return;
        _upsertDevice(phone);
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

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _scanError = null;
    });
    try {
      _sub?.cancel();
      _sub = _discovery.devicesStream.listen((list) {
        if (!mounted) return;
        for (final d in list) {
          _upsertDevice(d, notify: false);
        }
        setState(() {});
      });
      await _discovery.start();
    } catch (e) {
      setState(() => _scanError = 'mDNS 启动失败：$e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _upsertDevice(DeviceInfoModel device, {bool notify = true}) {
    final key = device.deviceId.isNotEmpty
        ? device.deviceId
        : '${device.ip}:${device.port}';
    _devices[key] = device;
    if (notify && mounted) setState(() {});
  }

  List<DeviceInfoModel> get _deviceList => _devices.values.toList();

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
      _upsertDevice(device);
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
              tooltip: '重新扫描',
              onPressed: _startScan,
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
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '设备列表',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      '手机扫左侧二维码配对，或等待自动发现',
                                      style: TextStyle(
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
    if (_deviceList.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.92, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeInOut,
              builder: (context, value, child) {
                return Transform.scale(scale: value, child: child);
              },
              child: Icon(
                Icons.phonelink_setup_rounded,
                size: 64,
                color: PhotoLinkTheme.brand.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '暂未发现 / 配对手机',
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

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _deviceList.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final d = _deviceList[index];
        return FadeSlideIn(
          delay: Duration(milliseconds: 40 * index),
          offsetY: 10,
          child: Material(
            color: const Color(0xFFF8FBFA),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _connect(d),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: PhotoLinkTheme.brand.withValues(alpha: 0.12),
                      ),
                      child: const Icon(
                        Icons.phone_android_rounded,
                        color: PhotoLinkTheme.brand,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.deviceName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${d.ip}:${d.port}',
                            style: const TextStyle(color: Color(0xFF5A6F6D)),
                          ),
                          if (d.osVersion.isNotEmpty)
                            Text(
                              d.osVersion,
                              style: const TextStyle(
                                color: Color(0xFF8A9C9A),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: () => _connect(d),
                      child: const Text('连接'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
