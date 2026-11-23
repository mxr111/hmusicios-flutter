import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'endpoints.dart';

/// 网关错误：只保留「阶段 / 状态 / 会话失效」，不把响应体写进异常。
class HuaweiException implements Exception {
  const HuaweiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class _RawResponse {
  const _RawResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

/// 与沐语 Go 版 internal/gateway 对等的网络层。
///
/// REA 运行时取证（读 Muyu.exe 进程堆）抓到真实 URL：
/// https://api-drcn.music.dbankcloud.cn/music-userbehavior-service/v1/service/favorite/simple/exist?contentID=..&contentType=1
/// 即「域名 + 完整路径 + ?query 原样拼接」。早期 iOS 版把 ? 编码成 %3F 导致 404，
/// 这里用 Uri 的 query 字段单独承载，保证 & = 不被转义。
class HuaweiGateway {
  HuaweiGateway({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;
  String? accessToken;
  late String deviceId = _newDeviceId();

  static String _newDeviceId() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  Uri makeUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path);
    }
    final mark = path.indexOf('?');
    if (mark < 0) {
      return Uri(scheme: 'https', host: HuaweiPaths.host, path: path);
    }
    return Uri(
      scheme: 'https',
      host: HuaweiPaths.host,
      path: path.substring(0, mark),
      query: path.substring(mark + 1),
    );
  }

  /// REA 观察 + 运行时内存里可见的请求头。
  Map<String, String> headers() => <String, String>{
        'x-client-version': HuaweiPaths.clientVersion,
        'x-deviceid': deviceId,
        'x-musicuuid': deviceId,
        'x-hw-client': HuaweiPaths.packageName,
        'x-client-package': HuaweiPaths.packageName,
        'x-device-context': HuaweiPaths.deviceContext,
        'x-recommend': '1',
        'Accept': 'application/json',
        'Accept-Language': 'zh-CN',
        'Accept-Lang': 'zh-CN',
        'Content-Type': 'application/json; charset=utf-8',
        'User-Agent':
            '${HuaweiPaths.packageName}/${HuaweiPaths.clientVersion} (iPadOS; MuyuFlutter)',
        if (accessToken != null && accessToken!.isNotEmpty)
          'Authorization': 'Bearer $accessToken',
      };

  /// 带 query 的接口先 GET；服务端只收 POST（404/405）时自动带 JSON body 重试。
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic> body = const <String, dynamic>{},
  }) async {
    final url = makeUrl(path);
    final preferGet = path.contains('?');
    var raw = await _send(url, preferGet ? 'GET' : 'POST', body);
    if (preferGet && (raw.statusCode == 404 || raw.statusCode == 405)) {
      raw = await _send(url, 'POST', body);
    }
    return _decode(raw, path);
  }

  Future<Map<String, dynamic>> get(String path) async {
    final raw = await _send(makeUrl(path), 'GET', const <String, dynamic>{});
    return _decode(raw, path);
  }

  /// 取纯文本（歌词 LRC）。歌词地址通常是完整 URL。
  Future<String> fetchText(Uri url) async {
    try {
      final req = await _client.getUrl(url);
      headers().forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      return await resp.transform(utf8.decoder).join();
    } on SocketException catch (e) {
      throw HuaweiException('歌词下载失败：${e.message}');
    }
  }

  Future<_RawResponse> _send(
      Uri url, String method, Map<String, dynamic> body) async {
    try {
      final HttpClientRequest req = method == 'GET'
          ? await _client.getUrl(url)
          : await _client.postUrl(url);
      headers().forEach((k, v) => req.headers.set(k, v));
      if (method == 'POST') {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();
      return _RawResponse(resp.statusCode, text);
    } on HuaweiException {
      rethrow;
    } on SocketException catch (e) {
      throw HuaweiException('网络请求失败：${e.message}');
    } on HandshakeException catch (e) {
      throw HuaweiException('TLS 握手失败：${e.message}');
    } catch (e) {
      throw HuaweiException('请求失败：$e');
    }
  }

  Map<String, dynamic> _decode(_RawResponse raw, String path) {
    if (raw.statusCode == 401) {
      throw const HuaweiException('登录已失效，请重新登录华为账号', statusCode: 401);
    }
    if (raw.statusCode == 404) {
      throw HuaweiException('接口不存在 HTTP 404：$path', statusCode: 404);
    }
    if (raw.statusCode < 200 || raw.statusCode >= 300) {
      throw HuaweiException(
        '华为服务在 $path 阶段返回 HTTP ${raw.statusCode}。若为 401/403，多为请求签名未还原',
        statusCode: raw.statusCode,
      );
    }
    try {
      final decoded = jsonDecode(raw.body);
      if (decoded is! Map<String, dynamic>) {
        throw const HuaweiException('服务响应格式异常');
      }
      final code = HuaweiGateway.firstString(
          decoded, const ['resultCode', 'retCode', 'error_code']);
      if (code != null && !_isSuccess(code)) {
        if (code == '401' || code == '1001' || code.toLowerCase().contains('token')) {
          throw const HuaweiException('登录已失效，请重新登录');
        }
        throw HuaweiException('华为服务返回 $code：$path');
      }
      return decoded;
    } on HuaweiException {
      rethrow;
    } on FormatException {
      throw const HuaweiException('服务响应不是合法 JSON');
    }
  }

  static bool _isSuccess(String code) {
    final c = code.toLowerCase();
    return c == '0' || c == '200' || c == 'ok' || c == 'success' || c.isEmpty;
  }

  /// 容错取值：字段缺失给默认值，避免单个可选字段让整体解析失败。
  static String? firstString(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v is String && v.isNotEmpty) return v;
      if (v is num) return v.toString();
    }
    return null;
  }

  static int? firstInt(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final n = int.tryParse(v);
        if (n != null) return n;
      }
    }
    return null;
  }

  static Uri? firstUrl(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v is String && v.isNotEmpty) return normalizeUrl(v);
    }
    return null;
  }

  static Uri? normalizeUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final direct = Uri.tryParse(s);
    if (direct != null && direct.hasScheme) return direct;
    return Uri.tryParse('https:${s.startsWith('//') ? '' : '//'}$s');
  }

  void dispose() => _client.close();
}
