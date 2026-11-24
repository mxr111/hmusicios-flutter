import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../services/app_log.dart';
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
  MusicSession({
    required this.token,
    required this.snsUserId,
    this.expireTime = '',
  });
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
    _client.userAgent =
        '${HuaweiPaths.packageName}/${HuaweiPaths.clientVersion} (iPadOS; MuyuFlutter)';
  }

  final HttpClient _client;
  final Random _random = Random.secure();

  /// 音乐会话（业务请求必需）。
  MusicSession? session;

  /// OAuth 账号 access token（仅用于换音乐会话，不直接发业务请求）。
  String? accountToken;

  /// 实测 refresh_token 不可用，但保留字段便于诊断与后续服务端策略变化。
  String? refreshToken;

  /// 会话变化回调：用于把新 token 持久化，避免重启后重新扫码。
  void Function()? onSessionChanged;

  late final String deviceId = _newDeviceId();

  String _newDeviceId() =>
      List.generate(32, (_) => _random.nextInt(16).toRadixString(16)).join();

  /// 运行时取证：Authorization 的 nonce 是 24 个随机字节的 48 位小写 hex，
  /// 不是 24 位字母数字（后者会被网关判为无效凭据）。
  String _nonce() {
    final buffer = StringBuffer();
    for (var i = 0; i < 24; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Digest 鉴权头。token 为空时用于 loginex（无会话调用）。
  String digestHeader([String? token]) {
    final created =
        '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';
    final buf = StringBuffer(
      'Digest username=app-music-baseline, nonce=${_nonce()}, created=$created',
    );
    final t = token ?? session?.token;
    if (t != null && t.isNotEmpty) buf.write(', token=$t');
    return buf.toString();
  }

  Map<String, String> headers([String? tokenOverride]) => <String, String>{
    // 运行时取证（Muyu 2.0.4 实际 HTTP/1.1 请求）：
    // Host / User-Agent=设备串 / Accept / Authorization / Content-Type /
    // Accept-Encoding。没有 x-client-version、x-deviceid 等头。
    // 多余的 x-* 头会让华为网关返回 990000。
    'User-Agent': HuaweiPaths.deviceContext,
    'Accept': 'application/json',
    'Accept-Encoding': 'gzip',
    'Content-Type': 'application/json;charset=UTF-8',
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
    final token =
        firstString(json, const ['token']) ?? _findDeep(json, const ['token']);
    final userId =
        firstString(json, const ['snsUserID', 'snsUserId']) ??
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
    onSessionChanged?.call();
    return s;
  }

  /// 华为账号 OAuth userinfo（需要授权时的 openid + profile scope）。
  /// 返回 nickname / picture 等资料；scope 不含 profile 时可能只有 sub。
  Future<Map<String, dynamic>> accountUserInfo(String accessToken) async {
    final req = await _client.getUrl(
      Uri.https(HuaweiPaths.tokenHost, HuaweiPaths.userInfoPath),
    );
    req.headers.set('Authorization', 'Bearer $accessToken');
    req.headers.set('Accept', 'application/json');
    req.headers.set('User-Agent', HuaweiPaths.deviceContext);
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode == 401) {
      throw const HuaweiException('账号资料授权已过期', statusCode: 401);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300 || body.isEmpty) {
      throw HuaweiException('账号资料请求失败（HTTP ${resp.statusCode}）');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const HuaweiException('账号资料响应格式异常');
    }
    return decoded;
  }

  /// 音乐侧账号资料：优先 GET，部分网关版本只接受 POST，因此两种都试一次。
  /// 失败时返回 null，由调用方保留已有资料，不影响登录和业务请求。
  Future<Map<String, dynamic>?> musicUserInfo() async {
    if (session == null) return null;
    for (final method in const <String>['GET', 'POST']) {
      try {
        final raw = await _send(
          makeUrl(HuaweiPaths.musicUserInfo),
          method,
          const <String, dynamic>{},
        );
        final json = _decode(raw, HuaweiPaths.musicUserInfo);
        if (json.isNotEmpty) return json;
      } on HuaweiException {
        // 404/405 或业务码不兼容时换下一种方法；两种都失败就回退已有资料。
      }
    }
    return null;
  }

  /// 业务 POST（源码事实：所有业务接口用 POST/JSON）。
  /// 音乐 token 失效时，用仍有效的账号 access token 自动换一次会话。
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic> body = const <String, dynamic>{},
  }) => _withSessionRetry(() async {
    final raw = await _send(makeUrl(path), 'POST', body);
    return _decode(raw, path);
  });

  /// GET（仅用于带 query 且源码明确 GET 的接口，如 favorite/exist、playlist/detail）。
  Future<Map<String, dynamic>> get(String path) => _withSessionRetry(() async {
    final raw = await _send(makeUrl(path), 'GET', const <String, dynamic>{});
    return _decode(raw, path);
  });

  Future<T> _withSessionRetry<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on HuaweiException catch (e) {
      final at = accountToken;
      if (e.statusCode != 401 || at == null || at.isEmpty) rethrow;
      await exchangeMusicToken(at);
      return await work();
    }
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
    return const [
      '.dbankcdn.cn',
      '.tingmall.com',
      '.kuke.com',
    ].any((s) => host.endsWith(s) && host.length > s.length);
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
          req.headers.contentType = ContentType.parse(
            'application/x-www-form-urlencoded',
          );
        } else {
          req.headers.contentType = ContentType.parse(
            'application/json;charset=UTF-8',
          );
        }
        req.write(
          form
              ? body.entries
                    .map(
                      (e) =>
                          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value.toString())}',
                    )
                    .join('&')
              : jsonEncode(body),
        );
      }
      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();
      AppLog.add(
        'http',
        '$method ${url.path} -> ${resp.statusCode} ${text.length}B',
      );
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
    refreshToken = firstString(json, const ['refresh_token']);
    onSessionChanged?.call();
    return at;
  }

  Map<String, dynamic> _decodeJson(_RawResponse raw, String path) {
    if (raw.statusCode == 401) {
      throw const HuaweiException('登录已失效，请重新登录华为账号', statusCode: 401);
    }
    if (raw.body.isEmpty) {
      throw HuaweiException(
        '$path 返回空响应（HTTP ${raw.statusCode}）',
        statusCode: raw.statusCode,
      );
    }
    try {
      final decoded = jsonDecode(raw.body);
      if (decoded is! Map<String, dynamic>) {
        throw const HuaweiException('服务响应格式异常');
      }
      // 业务码：源码事实 result.resultCode == 000000；
      // OAuth token 端点无 result 信封，直接返回 access_token。
      final result = decoded['result'];
      if (result is Map) {
        final code = firstString(Map<String, dynamic>.from(result), const [
          'resultCode',
        ]);
        final msg =
            firstString(Map<String, dynamic>.from(result), const [
              'resultMessage',
            ]) ??
            '';
        if (code != null && code != HuaweiPaths.successCode) {
          AppLog.add('api', '$path -> $code ${msg.isEmpty ? '' : msg}');
          if (code == '142400') {
            throw const HuaweiException('该歌曲当前不可播放（无版权 / 已下架 / 会员限制）');
          }
          if (code == '990000') {
            throw const HuaweiException('华为鉴权失败，请重新登录华为账号');
          }
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
        throw HuaweiException(
          '$path 阶段返回 HTTP ${raw.statusCode}',
          statusCode: raw.statusCode,
        );
      }
      return decoded;
    } on HuaweiException {
      rethrow;
    } on FormatException {
      throw const HuaweiException('服务响应不是合法 JSON');
    }
  }

  Map<String, dynamic> _decode(_RawResponse raw, String path) =>
      _decodeJson(raw, path);

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

  /// 在嵌套响应里找第一个非空字符串（华为资料常包在 data/profile 下）。
  static String? findDeepString(dynamic root, List<String> keys) {
    if (root is Map) {
      final direct = firstString(Map<String, dynamic>.from(root), keys);
      if (direct != null) return direct;
      for (final v in root.values) {
        final found = findDeepString(v, keys);
        if (found != null) return found;
      }
    } else if (root is List) {
      for (final v in root) {
        final found = findDeepString(v, keys);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// 在嵌套响应里找第一个可解析 URL。
  static Uri? findDeepUrl(dynamic root, List<String> keys) {
    if (root is Map) {
      final direct = firstUrl(Map<String, dynamic>.from(root), keys);
      if (direct != null) return direct;
      for (final v in root.values) {
        final found = findDeepUrl(v, keys);
        if (found != null) return found;
      }
    } else if (root is List) {
      for (final v in root) {
        final found = findDeepUrl(v, keys);
        if (found != null) return found;
      }
    }
    return null;
  }

  static String? _findDeep(dynamic root, List<String> keys) =>
      findDeepString(root, keys);

  void dispose() => _client.close();
}
