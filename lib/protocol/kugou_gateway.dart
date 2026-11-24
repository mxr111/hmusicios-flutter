import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 酷狗安卓公开盐。来自公开协议，待真机验证。
const String kugouAndroidSalt = 'OIlwieks28dk2k092lksi2UIkp';

/// 取流 `key` 参数的固定盐。
const String kugouPlaybackSalt = '57ae12eb6890223e355ccfcb74edf70d';

const String kugouAppId = '1005';
const String kugouClientVersion = '11070';
const String kugouSearchUserAgent =
    'Android14-1070-11070-201-0-SearchSong-wifi';
const String kugouDiscoveryUserAgent =
    'Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi';

/// 酷狗接口异常。失败时只抛出明确原因，不用空数据掩盖错误。
class KugouException implements Exception {
  const KugouException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

/// 酷狗会话：token/userid/dfid/mid 均可由用户手动填入。
class KugouSession {
  const KugouSession({
    required this.token,
    required this.userId,
    this.dfid = '-',
    this.mid = '',
    this.nickname = '',
    this.avatarUrl = '',
    this.vipType = 0,
    this.cookies = const <String, String>{},
  });

  final String token;
  final String userId;
  final String dfid;
  final String mid;
  final String nickname;
  final String avatarUrl;
  final int vipType;

  /// 原始 Cookie 键值，保留用户额外填入的字段。
  final Map<String, String> cookies;

  KugouSession copyWith({
    String? token,
    String? userId,
    String? dfid,
    String? mid,
    String? nickname,
    String? avatarUrl,
    int? vipType,
    Map<String, String>? cookies,
  }) {
    return KugouSession(
      token: token ?? this.token,
      userId: userId ?? this.userId,
      dfid: dfid ?? this.dfid,
      mid: mid ?? this.mid,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      vipType: vipType ?? this.vipType,
      cookies: cookies ?? this.cookies,
    );
  }

  /// 兼容 `Cookie: token=...; userid=...` 和逐项 Map 两种填法。
  factory KugouSession.fromCookies(Map<String, dynamic> input) {
    final values = <String, String>{};

    void put(String key, dynamic value) {
      if (value == null) return;
      final text = '$value'.trim();
      if (text.isEmpty) return;
      values[key.trim()] = text;
    }

    void parseCookieText(String text) {
      for (final part in text.split(';')) {
        final index = part.indexOf('=');
        if (index <= 0) continue;
        put(part.substring(0, index), part.substring(index + 1));
      }
    }

    for (final entry in input.entries) {
      final key = entry.key.trim();
      final lower = key.toLowerCase();
      if ((lower == 'cookie' || lower == 'set-cookie') &&
          entry.value is String) {
        parseCookieText(entry.value as String);
      } else {
        put(key, entry.value);
      }
    }

    String read(List<String> keys) {
      for (final key in keys) {
        final direct = values[key];
        if (direct != null && direct.isNotEmpty) return direct;
        for (final entry in values.entries) {
          if (entry.key.toLowerCase() == key.toLowerCase() &&
              entry.value.isNotEmpty) {
            return entry.value;
          }
        }
      }
      return '';
    }

    final token = read(const [
      'token',
      'user_token',
      'access_token',
      'KUGOU_API_TOKEN',
    ]);
    final userId = read(const [
      'userid',
      'user_id',
      'kugouid',
      'kugou_id',
      'uid',
      'KUGOU_API_USERID',
    ]);
    final dfid = read(const ['dfid', 'kg_dfid', 'KUGOU_API_DFID']);
    final mid = read(const ['mid', 'kg_mid', 'KUGOU_API_MID']);
    final nickname = read(const ['nickname', 'nick', 'user_name', 'username']);
    final avatar = read(const ['avatar', 'avatar_url', 'user_pic', 'pic']);
    final vipType =
        int.tryParse(read(const ['vip_type', 'vipType', 'viptype', 'vip'])) ??
        0;

    return KugouSession(
      token: token,
      userId: userId,
      dfid: dfid.isEmpty ? '-' : dfid,
      mid: mid,
      nickname: nickname,
      avatarUrl: avatar,
      vipType: vipType,
      cookies: Map<String, String>.unmodifiable(values),
    );
  }

  String get cookieHeader {
    final values = <String, String>{...cookies};
    void setIfMissing(String key, String value) {
      if (value.isEmpty) return;
      values.putIfAbsent(key, () => value);
    }

    setIfMissing('token', token);
    setIfMissing('userid', userId);
    setIfMissing('dfid', dfid);
    setIfMissing('kg_dfid', dfid);
    setIfMissing('mid', mid);
    setIfMissing('kg_mid', mid);
    return values.entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }
}

/// 酷狗安卓签名（纯函数，可单测）。
///
/// 来自公开协议，待真机验证：
/// `MD5(salt + 按 key 排序的 k=v 拼接 + body + salt)`。
String kugouSignature(
  Map<String, String> params, {
  String body = '',
  String salt = kugouAndroidSalt,
}) {
  final keys = params.keys.toList()..sort();
  final buffer = StringBuffer(salt);
  for (final key in keys) {
    buffer
      ..write(key)
      ..write('=')
      ..write(params[key] ?? '');
  }
  buffer
    ..write(body)
    ..write(salt);
  return md5.convert(utf8.encode(buffer.toString())).toString();
}

/// 搜索签名的语义化别名，便于业务层和单测直接调用。
String kugouSearchSignature(Map<String, String> params, {String body = ''}) =>
    kugouSignature(params, body: body);

/// 酷狗 v5/url 的额外 `key` 参数（纯函数，可单测）。
String kugouPlaybackKey({
  required String hash,
  required String mid,
  String userId = '0',
  String appId = kugouAppId,
}) {
  return md5
      .convert(utf8.encode('$hash$kugouPlaybackSalt$appId$mid$userId'))
      .toString();
}

class KugouGateway {
  KugouGateway({HttpClient? client, String? mid, String dfid = '-'})
    : _client = client ?? HttpClient(),
      deviceMid = (mid == null || mid.trim().isEmpty) ? _newMid() : mid.trim(),
      deviceDfid = dfid.trim().isEmpty ? '-' : dfid.trim() {
    _client.connectionTimeout = const Duration(seconds: 12);
  }

  static const String gatewayBase = 'https://gateway.kugou.com';
  static const String searchBase = 'https://complexsearch.kugou.com';
  static const String lyricsBase = 'https://krcs.kugou.com';
  static const String getdataBase = 'https://wwwapi.kugou.com';

  final HttpClient _client;
  final String deviceMid;
  String deviceDfid;

  KugouSession? session;

  bool get isLoggedIn {
    final current = session;
    return current != null &&
        current.token.isNotEmpty &&
        current.userId.isNotEmpty;
  }

  static String _newMid() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  void signInWithCookies(Map<String, dynamic> cookies) {
    final parsed = KugouSession.fromCookies(cookies);
    session = parsed;
  }

  void signOut() => session = null;

  void dispose() => _client.close();

  String get _mid {
    final value = session?.mid ?? '';
    return value.isNotEmpty ? value : deviceMid;
  }

  String get _dfid {
    final value = session?.dfid ?? '';
    return value.isNotEmpty ? value : deviceDfid;
  }

  Map<String, String> commonParams({
    String? clientTime,
    String appId = kugouAppId,
    String clientVersion = kugouClientVersion,
  }) {
    final current = session;
    final userId = current?.userId.isNotEmpty == true ? current!.userId : '0';
    final params = <String, String>{
      'dfid': _dfid,
      'mid': _mid,
      'uuid': '-',
      'appid': appId,
      'clientver': clientVersion,
      'clienttime':
          clientTime ?? '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'userid': userId,
    };
    final token = current?.token ?? '';
    if (token.isNotEmpty) params['token'] = token;
    return params;
  }

  Map<String, String> signedQuery(
    Map<String, String> params, {
    String body = '',
  }) {
    final query = Map<String, String>.of(params);
    query['signature'] = kugouSignature(query, body: body);
    return query;
  }

  static String signature(Map<String, String> params, {String body = ''}) =>
      kugouSignature(params, body: body);

  static String searchSignature(
    Map<String, String> params, {
    String body = '',
  }) => kugouSignature(params, body: body);

  /// 通用签名请求：查询参数与 JSON 请求体都参与签名。
  Future<Map<String, dynamic>> request(
    String baseUrl,
    String path, {
    String method = 'GET',
    Map<String, String> params = const <String, String>{},
    Object? body,
    String? xRouter,
    String? userAgent,
    Map<String, String> extraHeaders = const <String, String>{},
    String? clientTime,
    String appId = kugouAppId,
    String clientVersion = kugouClientVersion,
  }) async {
    final query = commonParams(
      clientTime: clientTime,
      appId: appId,
      clientVersion: clientVersion,
    );
    query.addAll(params);
    final bodyText = body == null
        ? ''
        : body is String
        ? body
        : jsonEncode(body);
    query['signature'] = kugouSignature(query, body: bodyText);
    final uri = _mergeUri(baseUrl, path, query);
    final headers = <String, String>{
      'User-Agent': userAgent ?? kugouDiscoveryUserAgent,
      'Accept': 'application/json',
      'dfid': query['dfid'] ?? _dfid,
      'mid': query['mid'] ?? _mid,
      'clienttime': query['clienttime'] ?? '',
      'kg-rc': '1',
      'kg-thash': '5d816a0',
      'kg-rec': '1',
      'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
    };
    final cookie = session?.cookieHeader ?? '';
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;
    if (xRouter != null && xRouter.isNotEmpty) headers['x-router'] = xRouter;
    headers.addAll(extraHeaders);

    final request = await _client.openUrl(method, uri);
    headers.forEach((key, value) {
      if (value.isNotEmpty) request.headers.set(key, value);
    });
    if (method != 'GET' && bodyText.isNotEmpty) {
      request.headers.contentType = ContentType.json;
      request.write(bodyText);
    }
    return _readJson(request, '$baseUrl$path');
  }

  /// 非签名 GET（歌词 krcs 等）。
  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final request = await _client.getUrl(uri);
    final headers = <String, String>{
      'User-Agent': kugouDiscoveryUserAgent,
      'Accept': 'application/json',
      ...extraHeaders,
    };
    headers.forEach((key, value) {
      if (value.isNotEmpty) request.headers.set(key, value);
    });
    return _readJson(request, '$uri');
  }

  Future<Map<String, dynamic>> _readJson(
    HttpClientRequest request,
    String label,
  ) async {
    try {
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final text = await utf8.decoder.bind(response).join();
      final cleaned = text
          .replaceAll('<!--KG_TAG_RES_START-->', '')
          .replaceAll('<!--KG_TAG_RES_END-->', '')
          .trim();
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw KugouException(
          '酷狗登录状态无效或该歌曲无权限',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw KugouException(
          '$label 返回 HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
      if (cleaned.isEmpty) {
        throw KugouException('$label 返回空响应');
      }
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map<String, dynamic>) {
        throw KugouException('$label 响应不是 JSON 对象');
      }
      final errorCode = _firstInt(decoded, const [
        'error_code',
        'errcode',
        'ErrorCode',
      ]);
      final status = _firstInt(decoded, const ['status']);
      final message = _firstString(decoded, const [
        'error_msg',
        'errmsg',
        'error',
        'msg',
        'message',
      ]);
      if (errorCode != null &&
          errorCode != 0 &&
          !(errorCode == 200 && status == 200)) {
        throw KugouException(
          '酷狗业务错误 $errorCode${message == null ? '' : '：$message'}',
          code: '$errorCode',
        );
      }
      if (status != null && status != 1 && status != 200) {
        throw KugouException(
          '酷狗业务状态 $status${message == null ? '' : '：$message'}',
          code: '$status',
        );
      }
      return decoded;
    } on KugouException {
      rethrow;
    } on SocketException catch (error) {
      throw KugouException('酷狗网络请求失败：${error.message}');
    } on HandshakeException catch (error) {
      throw KugouException('酷狗 TLS 握手失败：${error.message}');
    } on FormatException {
      throw KugouException('$label 响应不是合法 JSON');
    } on TimeoutException {
      throw const KugouException('酷狗请求超时');
    } catch (error) {
      throw KugouException('酷狗请求失败：$error');
    }
  }

  static Uri _mergeUri(String baseUrl, String path, Map<String, String> query) {
    final base = Uri.parse(baseUrl);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return base.replace(path: normalizedPath, queryParameters: query);
  }

  /// 搜索 URL（纯函数，离线可测）。
  static Uri searchUri({
    required String keyword,
    int page = 1,
    int pageSize = 30,
    String mid = '',
    String dfid = '-',
    String userId = '0',
    String token = '',
    String? clientTime,
  }) {
    final query = _baseQuery(
      mid: mid,
      dfid: dfid,
      userId: userId,
      token: token,
      clientTime: clientTime,
    );
    query.addAll(<String, String>{
      'keyword': keyword,
      'page': '$page',
      'pagesize': '$pageSize',
      'platform': 'AndroidFilter',
      'iscorrection': '1',
      'privilegefilter': '0',
      'area_code': '1',
      'dopicfull': '1',
      'albumhide': '0',
      'nocollect': '0',
    });
    query['signature'] = kugouSignature(query);
    return Uri.https('complexsearch.kugou.com', '/v2/search/song', query);
  }

  /// v5/url 取流 URL（纯函数，离线可测）。
  static Uri urlUri({
    required String hash,
    String albumAudioId = '',
    String albumId = '',
    String quality = 'flac',
    String mid = '',
    String dfid = '-',
    String userId = '0',
    String token = '',
    String appId = kugouAppId,
    String? clientTime,
  }) {
    final query = _baseQuery(
      mid: mid,
      dfid: dfid,
      userId: userId,
      token: token,
      clientTime: clientTime,
      appId: appId,
      clientVersion: '11430',
    );
    query.addAll(<String, String>{
      'hash': hash,
      'album_id': albumId,
      'album_audio_id': albumAudioId,
      'quality': quality,
      'area_code': '1',
      'ssa_flag': 'is_fromtrack',
      'version': '11430',
      'page_id': '151369488',
      'behavior': 'play',
      'pid': '2',
      'cmd': '26',
      'pidversion': '3001',
      'IsFreePart': '0',
      'ppage_id': '463467626,350369493,788954147',
      'cdnBackup': '1',
      'module': '',
      'clientver': '11430',
      'key': kugouPlaybackKey(
        hash: hash,
        mid: mid,
        userId: userId,
        appId: appId,
      ),
    });
    query['signature'] = kugouSignature(query);
    return Uri.https('gateway.kugou.com', '/v5/url', query);
  }

  /// 旧版 getdata 兜底 URL（纯函数，离线可测）。
  static Uri getdataUri({
    required String hash,
    String albumId = '',
    String mid = '',
    String dfid = '-',
  }) {
    return Uri.https('wwwapi.kugou.com', '/yy/index.php', <String, String>{
      'r': 'play/getdata',
      'hash': hash,
      'album_id': albumId,
      'dfid': dfid,
      'mid': mid,
      'platid': '4',
      'appid': '1014',
    });
  }

  /// krcs 歌词候选搜索 URL（纯函数，离线可测）。
  static Uri lyricsSearchUri({required String hash, int durationMs = 0}) {
    return Uri.https('krcs.kugou.com', '/search', <String, String>{
      'ver': '1',
      'man': 'yes',
      'client': 'mobi',
      'keyword': '',
      'duration': '$durationMs',
      'hash': hash,
    });
  }

  /// krcs 歌词下载 URL（纯函数，离线可测）。
  static Uri lyricsDownloadUri({
    required String id,
    required String accessKey,
    String format = 'krc',
  }) {
    return Uri.https('krcs.kugou.com', '/download', <String, String>{
      'ver': '1',
      'client': 'mobi',
      'id': id,
      'accesskey': accessKey,
      'fmt': format,
      'charset': 'utf8',
    });
  }

  static Map<String, String> _baseQuery({
    required String mid,
    required String dfid,
    required String userId,
    required String token,
    String? clientTime,
    String appId = kugouAppId,
    String clientVersion = kugouClientVersion,
  }) {
    final query = <String, String>{
      'dfid': dfid.isEmpty ? '-' : dfid,
      'mid': mid,
      'uuid': '-',
      'appid': appId,
      'clientver': clientVersion,
      'clienttime':
          clientTime ?? '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'userid': userId.isEmpty ? '0' : userId,
    };
    if (token.isNotEmpty) query['token'] = token;
    return query;
  }

  static String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is num) return '$value';
    }
    return null;
  }

  static int? _firstInt(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }
}
