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

/// 音乐会话（源码事实 tinglan/internal/huawei/client.go Session）：
/// token 是 loginex 返回的音乐 token，不是 OAuth access token。
class MusicSession {
  MusicSession({required this.token, required this.snsUserId, this.expireTime = ''});
  final String token;
  final String snsUserId;
  final String expireTime;
}

/// 华为音乐网关。
///
/// 鉴权（源码事实，修正之前所有推测）：
///   Authorization: Digest username=app-music-baseline, nonce=24字符随机,
///                  created=UTC ISO8601 无毫秒, token=music token
/// 不是 Bearer。无会话调用（loginex）省略 token 段。
/// 业务成功需 HTTP 2xx 且 result.resultCode == "000000"。
class HuaweiGateway {
  HuaweiGateway({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.userAgent = '${HuaweiPaths.packageName}/${HuaweiPaths.clientVersion} (iPadOS; MuyuFlutter)';
  }

  final HttpClient _client;
  final Random _random = Random.secure();

  /// 音乐会话（业务请求必需）。
  MusicSession? session;

  /// OAuth 账号 access token（仅用于换音乐会话，不直接发业务请求）。
  String? accountToken;

  late final String deviceId = _newDeviceId();

  String _newDeviceId() =>
      List.generate(32, (_) => _random.nextInt(16).toRadixString(16)).join();

  String _nonce() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(24, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  /// Digest 鉴权头。token 为空时用于 loginex（无会话调用）。
  String digestHeader([String? token]) {
    final created = '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';
    final buf = StringBuffer('Digest username=app-music-baseline, nonce=${_nonce()}, created=$created');
    final t = token ?? session?.token;
    if (t != null && t.isNotEmpty) buf.write(', token=$t');
    return buf.toString();
  }

  Map<String, String> headers([String? tokenOverride]) => <String, String>{
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
        'Content-Type': 'application/json',
        'Authorization': digestHeader(tokenOverride),
      };

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

  /// 三段式第 2→3 步：用 OAuth 账号 access token 换音乐会话。
  /// 请求头用不含 token 的 Digest。
  Future<MusicSession> exchangeMusicToken(String accessToken) async {
    final raw = await _send(
      makeUrl(HuaweiPaths.loginEx),
      'POST',
      <String, dynamic>{'accessToken': accessToken},
      tokenOverride: '', // 无 token 的 Digest
    );
    final json = _decodeJson(raw, HuaweiPaths.loginEx);
    final token = firstString(json, const ['token']) ??
        _findDeep(json, const ['token']);
    final userId = firstString(json, const ['snsUserID', 'snsUserId']) ??
        _findDeep(json, const ['snsUserID', 'snsUserId']);
    if (token == null || userId == null) {
      throw const HuaweiException('音乐会话不完整：缺少 token 或 snsUserID');
    }
    final s = MusicSession(
      token: token,
      snsUserId: userId,
      expireTime: firstString(json, const ['expireTime']) ?? '',
    );
    session = s;
    accountToken = accessToken;
    return s;
  }

  /// 业务 POST（源码事实：所有业务接口用 POST/JSON）。
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic> body = const <String, dynamic>{},
  }) async {
    final raw = await _send(makeUrl(path), 'POST', body);
    return _decode(raw, path);
  }

  /// GET（仅用于带 query 且源码明确 GET 的接口，如 favorite/exist、playlist/detail）。
  Future<Map<String, dynamic>> get(String path) async {
    final raw = await _send(makeUrl(path), 'GET', const <String, dynamic>{});
    return _decode(raw, path);
  }

  /// 取纯文本（歌词 LRC/HMRC）。歌词地址通常是完整 URL，需 allowlist 校验。
  Future<String> fetchText(Uri url) async {
    if (!_safeResource(url)) {
      throw HuaweiException('歌词资源域名不在白名单：$url');
    }
    try {
      final req = await _client.getUrl(url);
      headers().forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HuaweiException('歌词下载 HTTP ${resp.statusCode}');
      }
      return await resp.transform(utf8.decoder).join();
    } on SocketException catch (e) {
      throw HuaweiException('歌词下载失败：${e.message}');
    }
  }

  /// 资源域名白名单（源码事实：dbankcdn.cn / tingmall.com / kuke.com）。
  bool _safeResource(Uri url) {
    if (url.scheme != 'https') return false;
    final host = url.host.toLowerCase();
    return const ['.dbankcdn.cn', '.tingmall.com', '.kuke.com']
        .any((s) => host.endsWith(s) && host.length > s.length);
  }

  Future<_RawResponse> _send(
    Uri url,
    String method,
    Map<String, dynamic> body, {
    String? tokenOverride,
    bool form = false,
  }) async {
    try {
      final HttpClientRequest req = method == 'GET'
          ? await _client.getUrl(url)
          : await _client.postUrl(url);
      final h = headers(tokenOverride);
      h.forEach((k, v) => req.headers.set(k, v));
      if (method == 'POST') {
        if (form) {
          req.headers.contentType = ContentType.parse('application/x-www-form-urlencoded');
        } else {
          req.headers.contentType = ContentType.json;
        }
        req.write(form ? body.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value.toString())}').join('&') : jsonEncode(body));
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

  /// 授权码兑换（form-urlencoded，不传 client_secret）。返回账号 access token。
  Future<String> exchangeOAuthCode(String code, String verifier) async {
    final form = <String, dynamic>{
      'grant_type': 'authorization_code',
      'client_id': HuaweiPaths.clientId,
      'redirect_uri': HuaweiPaths.redirectUri,
      'code': code,
      'code_verifier': verifier,
    };
    final raw = await _send(
      Uri.https(HuaweiPaths.tokenHost, HuaweiPaths.tokenPath),
      'POST',
      form,
      tokenOverride: '',
      form: true,
    );
    final json = _decodeJson(raw, 'code exchange');
    final at = firstString(json, const ['access_token']);
    if (at == null) throw const HuaweiException('授权码兑换未返回 access_token');
    accountToken = at;
    return at;
  }

  Map<String, dynamic> _decodeJson(_RawResponse raw, String path) {
    if (raw.statusCode == 401) {
      throw const HuaweiException('登录已失效，请重新登录华为账号', statusCode: 401);
    }
    if (raw.body.isEmpty) {
      throw HuaweiException('$path 返回空响应（HTTP ${raw.statusCode}）', statusCode: raw.statusCode);
    }
    try {
      final decoded = jsonDecode(raw.body);
      if (decoded is! Map<String, dynamic>) throw const HuaweiException('服务响应格式异常');
      // 业务码：源码事实 result.resultCode == 000000；
      // OAuth token 端点无 result 信封，直接返回 access_token。
      final result = decoded['result'];
      if (result is Map) {
        final code = firstString(Map<String, dynamic>.from(result), const ['resultCode']);
        final msg = firstString(Map<String, dynamic>.from(result), const ['resultMessage']) ?? '';
        if (code != null && code != HuaweiPaths.successCode) {
          final lower = msg.toLowerCase();
          if (code == '401' ||
              lower.contains('token expired') ||
              lower.contains('token has expired') ||
              msg.contains('token已过期') ||
              msg.contains('令牌已过期') ||
              msg.contains('登录已过期') ||
              msg.contains('会话已过期')) {
            throw const HuaweiException('登录已失效，请重新扫码登录', statusCode: 401);
          }
          throw HuaweiException('华为服务返回 $code：$path');
        }
      }
      if (raw.statusCode < 200 || raw.statusCode >= 300) {
        throw HuaweiException('$path 阶段返回 HTTP ${raw.statusCode}', statusCode: raw.statusCode);
      }
      return decoded;
    } on HuaweiException {
      rethrow;
    } on FormatException {
      throw const HuaweiException('服务响应不是合法 JSON');
    }
  }

  Map<String, dynamic> _decode(_RawResponse raw, String path) => _decodeJson(raw, path);

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

  static String? _findDeep(dynamic root, List<String> keys) {
    if (root is Map<String, dynamic>) {
      final direct = firstString(root, keys);
      if (direct != null) return direct;
      for (final v in root.values) {
        final found = _findDeep(v, keys);
        if (found != null) return found;
      }
    } else if (root is List) {
      for (final v in root) {
        final found = _findDeep(v, keys);
        if (found != null) return found;
      }
    }
    return null;
  }

  void dispose() => _client.close();
}
