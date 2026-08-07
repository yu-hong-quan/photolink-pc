import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 创建信任自签名证书的 HttpClient（仅局域网 PhotoLink 使用）
HttpClient createInsecureHttpClient() {
  final client = HttpClient();
  // 局域网自签名证书：允许坏证书，避免 TLS 握手失败
  client.badCertificateCallback = (cert, host, port) => true;
  client.connectionTimeout = const Duration(seconds: 8);
  return client;
}

/// 带自签名信任的 IOClient
IOClient createPhotoLinkHttpClient() {
  return IOClient(createInsecureHttpClient());
}

/// 统一 API 客户端封装
class PhotoLinkApiClient {
  PhotoLinkApiClient(this.baseUrl) : _client = createPhotoLinkHttpClient();

  final String baseUrl;
  final IOClient _client;

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: query);
  }

  Future<http.Response> get(
    String path, {
    Map<String, String>? query,
  }) {
    return _client.get(_uri(path, query)).timeout(const Duration(seconds: 20));
  }

  Future<http.Response> postJson(
    String path,
    String jsonBody, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    return _client
        .post(
          _uri(path),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonBody,
        )
        .timeout(timeout);
  }

  Future<http.StreamedResponse> postBytesStream({
    required String path,
    required Stream<List<int>> stream,
    required int contentLength,
    required String fileName,
    String contentType = 'application/octet-stream',
  }) {
    final request = http.StreamedRequest('POST', _uri(path));
    request.contentLength = contentLength;
    request.headers['Content-Type'] = contentType;
    request.headers['X-Filename'] = Uri.encodeComponent(fileName);
    stream.listen(
      request.sink.add,
      onError: request.sink.addError,
      onDone: request.sink.close,
      cancelOnError: true,
    );
    return _client.send(request).timeout(const Duration(minutes: 30));
  }

  Future<http.StreamedResponse> getStream(String path) {
    final request = http.Request('GET', _uri(path));
    return _client.send(request).timeout(const Duration(minutes: 30));
  }

  void close() => _client.close();
}
