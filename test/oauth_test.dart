import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/protocol/endpoints.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';
import 'package:muyu_flutter/protocol/huawei_oauth.dart';
import 'package:muyu_flutter/services/session_store.dart';

class _AuthRetryGateway extends HuaweiGateway {
  _AuthRetryGateway(this.failure);

  final Object failure;
  int calls = 0;
  int exchanges = 0;

  @override
  Future<Map<String, dynamic>> get(String path) async {
    calls++;
    if (calls == 1) throw failure;
    return <String, dynamic>{
      'result': <String, dynamic>{
        'songSimpleInfos': <dynamic>[
          <String, dynamic>{'contentID': 'daily-1', 'contentName': '每日一'},
        ],
      },
    };
  }

  @override
  Future<MusicSession> exchangeMusicToken(String accessToken) async {
    exchanges++;
    final updated = MusicSession(token: 'new-token', snsUserId: 'user');
    session = updated;
    accountToken = accessToken;
    return updated;
  }
}

void main() {
  test('PKCE challenge 与 verifier 严格对应（S256 / 无 padding）', () {
    final a = OAuthAttempt(random: Random(7), now: DateTime.utc(2026));
    final expected = base64Url
        .encode(sha256.convert(utf8.encode(a.verifier)).bytes)
        .replaceAll('=', '');
    expect(a.challenge, expected);
    expect(a.challenge, isNot(contains('=')));
    expect(a.verifier.length, 64);
    expect(a.state.length, 43);
  });

  test('授权 URL 使用源码端点与完整参数', () {
    final a = OAuthAttempt(random: Random(11), now: DateTime.utc(2026));
    final uri = a.authorizeUri;
    expect(uri.scheme, 'https');
    expect(uri.host, HuaweiPaths.authorizeHost);
    expect(uri.path, HuaweiPaths.authorizePath);
    expect(uri.queryParameters['client_id'], HuaweiPaths.clientId);
    expect(uri.queryParameters['redirect_uri'], 'hms://redirect_uri');
    expect(uri.queryParameters['response_type'], 'code');
    expect(uri.queryParameters['code_challenge_method'], 'S256');
    expect(uri.queryParameters['code_challenge'], a.challenge);
    expect(uri.queryParameters['state'], a.state);
  });

  test('接受正确的 hms://redirect_uri 回调并消费一次', () {
    final a = OAuthAttempt(random: Random(3), now: DateTime.now());
    final cb = a.accept('hms://redirect_uri?code=abc123&state=${a.state}');
    expect(cb.code, 'abc123');
    expect(
      () => a.accept('hms://redirect_uri?code=abc123&state=${a.state}'),
      throwsA(isA<HuaweiException>()),
    );
  });

  test('拒绝错误 state、error、重复参数与非回调 URL', () {
    final a = OAuthAttempt(random: Random(5), now: DateTime.now());
    expect(
      () => a.accept('hms://redirect_uri?code=x&state=wrong'),
      throwsA(isA<HuaweiException>()),
    );
    final b = OAuthAttempt(random: Random(6), now: DateTime.now());
    expect(
      () => b.accept('hms://redirect_uri?state=${b.state}&error=access_denied'),
      throwsA(isA<HuaweiException>()),
    );
    final c = OAuthAttempt(random: Random(8), now: DateTime.now());
    expect(
      () => c.accept('hms://redirect_uri?code=x&code=y&state=${c.state}'),
      throwsA(isA<HuaweiException>()),
    );
    final d = OAuthAttempt(random: Random(9), now: DateTime.now());
    expect(d.isCallback('https://example.com/?code=x'), isFalse);
    expect(d.isCallback('hms://redirect_uri/path?code=x'), isFalse);
    expect(d.isCallback('hms://redirect_uri?code=x#frag'), isFalse);
  });

  test('拒绝过期授权尝试', () {
    final a = OAuthAttempt(
      random: Random(13),
      now: DateTime.now().subtract(const Duration(minutes: 11)),
    );
    expect(
      () => a.accept('hms://redirect_uri?code=x&state=${a.state}'),
      throwsA(isA<HuaweiException>()),
    );
  });

  test('MusicSession expireTime 决定 isLoggedIn', () {
    final gateway = HuaweiGateway();
    final api = HuaweiAPI(gateway: gateway);

    gateway.session = MusicSession(
      token: 't',
      snsUserId: 'u',
      expireTime: '2020-01-01T00:00:00Z',
    );
    expect(api.isLoggedIn, isFalse);

    gateway.session = MusicSession(
      token: 't',
      snsUserId: 'u',
      expireTime: DateTime.now()
          .add(const Duration(hours: 1))
          .toUtc()
          .toIso8601String(),
    );
    expect(api.isLoggedIn, isTrue);

    gateway.session = MusicSession(token: 't', snsUserId: 'u');
    expect(api.isLoggedIn, isTrue, reason: '上游未给 expireTime 时保持兼容');
  });

  test('990000 / 990006 / 401 都触发一次会话刷新并重试', () async {
    for (final failure in <Object>[
      HuaweiBusinessException('990000', '鉴权失败'),
      const HuaweiException('华为服务返回 990006：User token expired!'),
      const HuaweiException('登录已失效，请重新扫码登录', statusCode: 401),
    ]) {
      final gateway = _AuthRetryGateway(failure)..accountToken = 'account';
      final api = HuaweiAPI(gateway: gateway);
      final songs = await api.daily30();
      expect(songs.single.id, 'daily-1');
      expect(gateway.exchanges, 1);
    }
  });

  test('会话快照分开保存 accountToken / refreshToken / expireTime', () {
    const snapshot = SessionSnapshot(
      huaweiAccountToken: 'account-token',
      huaweiRefreshToken: 'refresh-token',
      huaweiExpireTime: '2026-12-01T00:00:00Z',
    );
    final restored = SessionSnapshot.fromJson(snapshot.toJson());
    expect(restored.huaweiAccountToken, 'account-token');
    expect(restored.huaweiRefreshToken, 'refresh-token');
    expect(restored.huaweiExpireTime, '2026-12-01T00:00:00Z');
  });
}
