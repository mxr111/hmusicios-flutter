import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'endpoints.dart';
import 'huawei_gateway.dart';

/// 一次 OAuth PKCE 授权尝试。
///
/// 事实来源：tinglan/native/internal/huawei/auth.go。
/// - 授权端点 oauth-login.platform.hicloud.com/oauth2/v3/authorize
/// - redirect_uri 固定为 hms://redirect_uri，必须原样校验
/// - verifier 48 随机字节、state 32 随机字节，S256 challenge
/// - 回调只接受一次，10 分钟过期，拒绝重复参数 / 错误 state / error
class OAuthAttempt {
  OAuthAttempt({Random? random, DateTime? now})
      : _random = random ?? Random.secure(),
        createdAt = now ?? DateTime.now();

  final Random _random;
  final DateTime createdAt;

  bool _consumed = false;

  late final String verifier = _randomToken(48);
  late final String state = _randomToken(32);

  String _randomToken(int length) => base64Url
      .encode(List<int>.generate(length, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  /// RFC 7636 S256：BASE64URL(SHA256(ASCII(verifier)))，无 padding。
  String get challenge {
    final digest = sha256.convert(utf8.encode(verifier)).bytes;
    return base64Url.encode(digest).replaceAll('=', '');
  }

  Uri get authorizeUri => Uri.https(
        HuaweiPaths.authorizeHost,
        HuaweiPaths.authorizePath,
        <String, String>{
          'client_id': HuaweiPaths.clientId,
          'redirect_uri': HuaweiPaths.redirectUri,
          'response_type': 'code',
          'access_type': 'offline',
          'scope': 'openid',
          'state': state,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'countryCode': 'cn',
          'ui_locales': 'zh-cn',
        },
      );

  /// 严格识别 hms://redirect_uri?... 回调（与 auth.go IsCallback 对齐）。
  bool isCallback(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return false;
    if (uri.scheme.toLowerCase() != 'hms') return false;
    if (uri.host.toLowerCase() != 'redirect_uri') return false;
    if (uri.userInfo.isNotEmpty || uri.path.isNotEmpty) return false;
    if (raw.contains('#')) return false;
    return true;
  }

  /// 消费回调，返回授权码。任何异常都使本次尝试作废，必须重新授权。
  OAuthCallback accept(String raw) {
    if (_consumed) {
      throw const HuaweiException('授权尝试已结束，请重新打开登录页');
    }
    if (!isCallback(raw)) {
      throw const HuaweiException('回调地址不属于本次授权流程');
    }
    _consumed = true;

    final age = DateTime.now().difference(createdAt);
    if (age < Duration.zero || age > const Duration(minutes: 10)) {
      throw const HuaweiException('授权已超时，请重新登录');
    }

    final uri = Uri.parse(raw);
    for (final key in const <String>['state', 'code', 'error']) {
      if ((uri.queryParametersAll[key]?.length ?? 0) > 1) {
        throw HuaweiException('授权回调参数重复：$key');
      }
    }
    final q = uri.queryParameters;
    if (q['state'] != state) {
      throw const HuaweiException('授权状态不匹配，请重新登录');
    }
    final error = q['error'];
    if (error != null && error.isNotEmpty) {
      throw HuaweiException('华为账号授权被拒绝：$error');
    }
    final code = q['code'];
    if (code == null || code.isEmpty) {
      throw const HuaweiException('授权回调缺少 code');
    }
    return OAuthCallback(code: code);
  }
}

class OAuthCallback {
  const OAuthCallback({required this.code});

  final String code;
}
