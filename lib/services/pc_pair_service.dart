import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../core/models/device_info.dart';

/// PC 配对服务：展示二维码，接收 App 扫码后回传的手机设备信息
class PcPairService {
  PcPairService();

  HttpServer? _server;
  DeviceInfoModel? pcInfo;
  final _pairedController = StreamController<DeviceInfoModel>.broadcast();

  Stream<DeviceInfoModel> get pairedPhoneStream => _pairedController.stream;
  bool get isRunning => _server != null;

  /// 启动配对 HTTPS 服务，并生成本机 PC 信息（用于二维码）
  Future<DeviceInfoModel> start() async {
    if (_server != null && pcInfo != null) return pcInfo!;

    final ip = await _resolveLocalIp();
    pcInfo = DeviceInfoModel(
      deviceId: const Uuid().v4(),
      deviceName: Platform.localHostname,
      deviceType: 'pc',
      osVersion: Platform.operatingSystemVersion,
      ip: ip,
      // 二维码里的 port 指向配对端口
      port: PhotoLinkConst.pairPort,
    );

    final certData = await rootBundle.load('assets/certs/cert.pem');
    final keyData = await rootBundle.load('assets/certs/key.pem');
    final context = SecurityContext()
      ..useCertificateChainBytes(certData.buffer.asUint8List())
      ..usePrivateKeyBytes(keyData.buffer.asUint8List());

    final router = Router();
    router.get('/api/pc/info', (Request request) {
      return Response.ok(
        jsonEncode(pcInfo!.toJson()),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    });

    // App 扫码后把手机相册服务地址 POST 回来
    router.post('/api/pair', (Request request) async {
      try {
        final body = await request.readAsString();
        final map = jsonDecode(body) as Map<String, dynamic>;
        final phone = DeviceInfoModel.fromJson(map);
        if (phone.ip.isEmpty) {
          return Response(
            400,
            body: jsonEncode({'success': false, 'message': '缺少手机 IP'}),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
          );
        }
        if (!_pairedController.isClosed) {
          _pairedController.add(phone);
        }
        return Response.ok(
          jsonEncode({'success': true, 'message': '配对成功'}),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      } catch (e) {
        return Response(
          500,
          body: jsonEncode({'success': false, 'message': '$e'}),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }
    });

    _server = await shelf_io.serve(
      const Pipeline().addMiddleware(_cors()).addHandler(router.call),
      InternetAddress.anyIPv4,
      PhotoLinkConst.pairPort,
      securityContext: context,
    );
    return pcInfo!;
  }

  Middleware _cors() {
    const headers = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type',
    };
    return (Handler inner) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: headers);
        }
        final res = await inner(request);
        return res.change(headers: headers);
      };
    };
  }

  Future<String> _resolveLocalIp() async {
    final wifiIp = await NetworkInfo().getWifiIP();
    if (wifiIp != null && wifiIp.isNotEmpty) return wifiIp;
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    for (final ni in interfaces) {
      for (final addr in ni.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
    return '127.0.0.1';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> dispose() async {
    await stop();
    await _pairedController.close();
  }
}
