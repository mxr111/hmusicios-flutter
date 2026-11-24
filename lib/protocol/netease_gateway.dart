import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;

/// 网易云音乐 weapi 网关（REA 对 Muyu.exe internal/providers/netease 反编译复刻）。
/// - 模块事实：encryptCBC(0x14076e120) + weapiForm(0x14076e3a0) + post/postDesktop；
///   IV 实测 `0102030405060708`；cookie 实测 MUSIC_U / csrf_token。
/// - weapi 为标准双重 AES-CBC：第一层固定 key，第二层随机/固定 key + RSA encSecKey。
///   本实现用固定的第二层 key 与其预计算 encSecKey（网易云公开算法，服务端可正确解密）。
class NeteaseException implements Exception {
  const NeteaseException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}

class NeteaseSession {
  NeteaseSession({required this.musicU, this.csrf = '', this.nickname = '', this.userId = ''});
  final String musicU; // MUSIC_U cookie
  final String csrf; // csrf_token cookie
  final String nickname;
  final String userId;
}

class NeteaseGateway {
  NeteaseGateway({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0 Safari/537.36';
  }

  final HttpClient _client;
  static const String host = 'music.163.com';

  NeteaseSession? session;
  bool get isLoggedIn => session != null;

  // weapi 标准常量（NeteaseCloudMusicApi 公开算法；EXE encryptCBC 同类实现）。
  static const String _firstKey = '0CoJUm6Qyw8W8jud';
  static final List<int> _iv = utf8.encode('0102030405060708');
  // RSA 公钥（网易云 weapi 固定值）：modulus = 0x00e0b5...b8e7，exponent = 0x010001。
  static const String _modulusHex =
      '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b7251'
      '52b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312e'
      'cbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d'
      '813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';
  static const int _exponent = 0x010001;
  final Random _random = Random.secure();

  /// weapi 双重 AES-CBC 加密 + RSA encSecKey（标准可服务端解密）。
  Map<String, String> weapiForm(Map<String, dynamic> payload) {
    final text = jsonEncode(payload);
    // 第二层 key = 随机 16 字节可打印串。
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final secondKey = List.generate(
        16, (_) => chars.codeUnitAt(_random.nextInt(chars.length)));
    final first = _aesCbcEncrypt(text, utf8.encode(_firstKey));
    final second = _aesCbcEncrypt(first, secondKey);
    return <String, String>{
      'params': second,
      'encSecKey': _rsaEncSecKey(String.fromCharCodes(secondKey.reversed)),
      'csrf_token': session?.csrf ?? '',
    };
  }

  /// RSA(text reversed) mod modulus，输出 256 字节定长 hex（weapi 标准）。
  String _rsaEncSecKey(String reversed) {
    final n = BigInt.parse(_modulusHex, radix: 16);
    final m = BigInt.parse(
        reversed.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join(),
        radix: 16);
    final r = m.pow(_exponent) % n;
    return r.toRadixString(16).padLeft(256, '0');
  }

  /// AES-128-CBC + PKCS7，输出 Base64（encrypt 包，与 weapi 标准一致）。
  String _aesCbcEncrypt(String plain, List<int> key) {
    final encrypter = enc.Encrypter(enc.AES(
      enc.Key(Uint8List.fromList(key)),
      mode: enc.AESMode.cbc,
    ));
    final iv = enc.IV(Uint8List.fromList(_iv));
    return encrypter.encrypt(plain, iv: iv).base64;
  }

  /// weapi POST：/weapi/...，form 为加密后的 params/encSecKey。
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> payload,
      {bool withCookies = true}) async {
    final form = weapiForm(payload);
    final uri = Uri.https(host, path);
    final req = await _client.postUrl(uri);
    req.headers.contentType = ContentType.parse('application/x-www-form-urlencoded');
    req.headers.set('Referer', 'https://music.163.com/');
    req.headers.set('Origin', 'https://music.163.com');
    if (withCookies && session != null) {
      final cookies = <String>['MUSIC_U=${session!.musicU}'];
      if (session!.csrf.isNotEmpty) cookies.add('csrf_token=${session!.csrf}');
      req.headers.set('Cookie', cookies.join('; '));
    }
    req.write(form.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&'));
    final resp = await req.close();
    final body = await utf8.decoder.bind(resp).join();
    if (resp.statusCode != 200) {
      throw NeteaseException('网易云接口 HTTP ${resp.statusCode}',
          code: '${resp.statusCode}');
    }
    if (body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return <String, dynamic>{};
    // 网易云 code != 200 为业务失败。
    final code = decoded['code'];
    if (code is int && code != 200) {
      throw NeteaseException(
          '网易云业务错误 $code：${decoded['message'] ?? ''}', code: '$code');
    }
    return decoded;
  }

  /// GET（账号资料等少数非 weapi 接口）。
  Future<Map<String, dynamic>> get(String path,
      {Map<String, String>? query, bool withCookies = true}) async {
    final uri = Uri.https(host, path, query);
    final req = await _client.getUrl(uri);
    req.headers.set('Referer', 'https://music.163.com/');
    if (withCookies && session != null) {
      req.headers.set('Cookie', 'MUSIC_U=${session!.musicU}');
    }
    final resp = await req.close();
    final body = await utf8.decoder.bind(resp).join();
    if (body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  void signIn(NeteaseSession s) => session = s;

  void signOut() => session = null;

  void dispose() => _client.close();
}
