import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// QqException：QQ 音乐请求或响应不合法时抛出。
class QqException implements Exception {
  const QqException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// 端点全部来自 Muyu 2.0.4 二进制字符串。
class QqEndpoints {
  const QqEndpoints._();

  static const String search =
      'https://c.y.qq.com/soso/fcgi-bin/search_for_qq_cp';
  static const String lyric =
      'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg';
  static const String album =
      'https://c.y.qq.com/v8/fcg-bin/fcg_v8_album_info_cp.fcg';
  static const String comment =
      'https://c.y.qq.com/base/fcgi-bin/fcg_global_comment_h5.fcg';
  static const String musicu = 'https://u.y.qq.com/cgi-bin/musicu.fcg';
  static const String musics = 'https://u.y.qq.com/cgi-bin/musics.fcg';
  static const String qrShow = 'https://ssl.ptlogin2.qq.com/ptqrshow';
  static const String qrLogin = 'https://ssl.ptlogin2.qq.com/ptqrlogin';
  static const String audioCdn = 'https://isure.stream.qqmusic.qq.com/';
  static const String loginPage =
      'https://y.qq.com/portal/wx_redirect.html?login_type=1&surl=https://y.qq.com';
}

/// QQ 音乐 Cookie 会话。
///
/// Muyu 二进制中的 Cookie 字段为 `qqmusic_uin` / `qqmusic_key`；网页端
/// 同时使用 `qqmusic_u` / `uin` / `skey`，这里全部兼容。
class QqSession {
  const QqSession({
    required this.cookies,
    this.uin = '',
    this.key = '',
    this.nickname = '',
  });

  final Map<String, String> cookies;
  final String uin;
  final String key;
  final String nickname;

  bool get isLoggedIn =>
      cookies['qqmusic_key']?.isNotEmpty == true ||
      cookies['qqmusic_u']?.isNotEmpty == true ||
      cookies['uin']?.isNotEmpty == true ||
      cookies['skey']?.isNotEmpty == true;

  String get cookieHeader => cookies.entries
      .where((entry) => entry.value.isNotEmpty)
      .map((entry) => '${entry.key}=${entry.value}')
      .join('; ');

  factory QqSession.fromCookies(Map<String, dynamic> raw) {
    final cookies = <String, String>{};

    void add(String key, dynamic value) {
      final name = key.trim().toLowerCase();
      if (name.isEmpty || value == null) return;
      final text = value is List
          ? (value.isEmpty ? '' : '${value.first}')
          : '$value';
      final safe = text.replaceAll(RegExp(r'[\r\n]'), '').trim();
      if (safe.isNotEmpty) cookies[name] = safe;
    }

    for (final entry in raw.entries) {
      final key = entry.key.trim().toLowerCase();
      if ((key == 'cookie' || key == 'cookies') && entry.value is String) {
        for (final part in '${entry.value}'.split(';')) {
          final index = part.indexOf('=');
          if (index <= 0) continue;
          add(part.substring(0, index), part.substring(index + 1));
        }
      } else {
        add(key, entry.value);
      }
    }

    final rawUin =
        cookies['qqmusic_uin'] ??
        cookies['uin'] ??
        cookies['p_uin'] ??
        cookies['wxuin'] ??
        '';
    final uin = _normalizeUin(rawUin);
    final key = cookies['qqmusic_key'] ?? cookies['qqmusic_u'] ?? '';
    final nickname =
        cookies['nickname'] ??
        cookies['nick'] ??
        cookies['name'] ??
        cookies['displayname'] ??
        '';

    return QqSession(cookies: cookies, uin: uin, key: key, nickname: nickname);
  }

  static String _normalizeUin(String raw) {
    var value = raw.trim();
    if (value.toLowerCase().startsWith('o')) value = value.substring(1);
    final match = RegExp(r'\d{4,}').firstMatch(value);
    return match?.group(0) ?? value.replaceAll(RegExp(r'[^0-9]'), '');
  }
}

/// QQ 音乐网关。所有请求固定带 `Referer: https://y.qq.com/` 与浏览器 UA。
class QqGateway {
  QqGateway({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0 Safari/537.36';
  }

  final HttpClient _client;

  QqSession? session;

  bool get isLoggedIn => session?.isLoggedIn == true;

  String get displayName {
    final current = session;
    if (current == null) return 'QQ 音乐';
    if (current.nickname.isNotEmpty) return current.nickname;
    if (current.uin.isNotEmpty) return 'QQ ${current.uin}';
    return 'QQ 音乐';
  }

  String get _uin {
    final value = session?.uin ?? '';
    return value.isEmpty ? '0' : value;
  }

  void signInWithCookies(Map<String, dynamic> cookies) {
    session = cookies.isEmpty ? null : QqSession.fromCookies(cookies);
  }

  void signOut() => session = null;

  void dispose() => _client.close();

  /// 与 Muyu `qq.zzcSign` 相同的 zzc 签名。
  ///
  /// 算法：SHA1(payload) 大写 hex → 两段索引拼接 + 20 字节异或混淆的
  /// base64（去掉 +/=）+ `zzc` 前缀，最后转小写。
  static String zzcSign(String payload) {
    final hash = sha1.convert(utf8.encode(payload)).toString().toUpperCase();
    const part1Indexes = <int>[23, 14, 6, 36, 16, 7, 19];
    const part2Indexes = <int>[16, 1, 32, 12, 19, 27, 8, 5];
    const scramble = <int>[
      89,
      39,
      179,
      150,
      218,
      82,
      58,
      252,
      177,
      52,
      186,
      123,
      120,
      64,
      242,
      133,
      143,
      161,
      121,
      179,
    ];

    final part1 = part1Indexes.map((index) => hash[index]).join();
    final part2 = part2Indexes.map((index) => hash[index]).join();
    final bytes = List<int>.generate(scramble.length, (index) {
      final value = int.parse(
        hash.substring(index * 2, index * 2 + 2),
        radix: 16,
      );
      return scramble[index] ^ value;
    });
    final part3 = base64.encode(bytes).replaceAll(RegExp(r'[+/=]'), '');
    return 'zzc$part1$part3$part2'.toLowerCase();
  }

  static String imageUrlForSongMid(String songmid) =>
      'https://y.gtimg.cn/music/photo_new/T002R800x800M000$songmid.jpg';

  static String imageUrlForAlbumMid(String albummid) =>
      imageUrlForSongMid(albummid);

  /// c.y.qq.com GET 接口。
  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    bool withCookies = true,
  }) async {
    try {
      final request = await _client.getUrl(uri);
      _applyHeaders(request);
      if (withCookies && session != null) {
        request.headers.set(HttpHeaders.cookieHeader, session!.cookieHeader);
      }
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw QqException(
          _httpMessage(response.statusCode),
          code: '${response.statusCode}',
        );
      }
      return _decodeMap(body);
    } on QqException {
      rethrow;
    } catch (_) {
      throw const QqException('QQ 音乐网络请求失败，请检查网络后重试');
    }
  }

  /// 表单 POST，用于 musicu.fcg / musics.fcg。
  Future<Map<String, dynamic>> postForm(
    Uri uri,
    Map<String, String> form, {
    bool withCookies = true,
  }) async {
    try {
      final request = await _client.postUrl(uri);
      _applyHeaders(request);
      request.headers.contentType = ContentType.parse(
        'application/x-www-form-urlencoded; charset=UTF-8',
      );
      if (withCookies && session != null) {
        request.headers.set(HttpHeaders.cookieHeader, session!.cookieHeader);
      }
      request.write(
        form.entries
            .map(
              (entry) =>
                  '${Uri.encodeQueryComponent(entry.key)}='
                  '${Uri.encodeQueryComponent(entry.value)}',
            )
            .join('&'),
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw QqException(
          _httpMessage(response.statusCode),
          code: '${response.statusCode}',
        );
      }
      return _decodeMap(body);
    } on QqException {
      rethrow;
    } catch (_) {
      throw const QqException('QQ 音乐网络请求失败，请检查网络后重试');
    }
  }

  /// 调用 musicu 模块。
  ///
  /// `signed=true` 时改走 `musics.fcg?sign=<zzcSign(data)>`。
  Future<Map<String, dynamic>> musicu({
    required String moduleKey,
    required Map<String, dynamic> module,
    bool signed = false,
    Map<String, dynamic>? comm,
  }) async {
    final commPayload = <String, dynamic>{
      'uin': _uin,
      'format': 'json',
      'ct': 24,
      'cv': 0,
      'platform': 'yqq.json',
      'g_tk': 5381,
      if (session?.key.isNotEmpty == true) 'authst': session!.key,
      ...?comm,
    };
    final payload = <String, dynamic>{'comm': commPayload, moduleKey: module};
    final data = jsonEncode(payload);
    final query = <String, String>{
      'format': 'json',
      'inCharset': 'utf8',
      'outCharset': 'utf-8',
      'notice': '0',
      'platform': 'yqq.json',
      'needNewCode': '0',
      'g_tk': '5381',
      'loginUin': _uin,
      'hostUin': '0',
      if (signed) 'sign': zzcSign(data),
    };
    final uri = Uri.https(
      'u.y.qq.com',
      signed ? '/cgi-bin/musics.fcg' : '/cgi-bin/musicu.fcg',
      query,
    );
    return postForm(uri, <String, String>{'data': data});
  }

  void _applyHeaders(HttpClientRequest request) {
    request.headers.set(HttpHeaders.refererHeader, 'https://y.qq.com/');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.acceptLanguageHeader, 'zh-CN,zh;q=0.9');
    request.headers.set('Origin', 'https://y.qq.com');
  }

  static Map<String, dynamic> _decodeMap(String body) {
    var text = body.trim();
    if (text.isEmpty) return <String, dynamic>{};
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    if (!text.startsWith('{')) {
      final first = text.indexOf('{');
      final last = text.lastIndexOf('}');
      if (first >= 0 && last > first) text = text.substring(first, last + 1);
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const QqException('QQ 音乐返回了无法解析的响应');
    }
    throw const QqException('QQ 音乐返回了非对象响应');
  }

  static String _httpMessage(int status) {
    if (status == HttpStatus.unauthorized) return 'QQ 音乐登录已失效，请重新登录';
    if (status == HttpStatus.forbidden) return 'QQ 音乐拒绝访问（403）';
    if (status == HttpStatus.tooManyRequests) return 'QQ 音乐请求过于频繁，请稍后重试';
    return 'QQ 音乐接口 HTTP $status';
  }
}
