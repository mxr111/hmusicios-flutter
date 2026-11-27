import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/services/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('会话快照可 JSON 往返，缺字段安全回落', () {
    const snapshot = SessionSnapshot(
      source: 'netease',
      huaweiToken: 'music-token',
      huaweiUserId: 'sns-1',
      huaweiAccountToken: 'account-token',
      huaweiNickname: '土豆',
      neteaseMusicU: 'music-u',
      neteaseCsrf: 'csrf',
      neteaseNickname: '云村用户',
      neteaseUserId: '42',
      themeIndex: 3,
    );
    final restored = SessionSnapshot.fromJson(snapshot.toJson());

    expect(restored.huaweiToken, 'music-token');
    expect(restored.huaweiUserId, 'sns-1');
    expect(restored.neteaseMusicU, 'music-u');
    expect(restored.themeIndex, 3);
    expect(SessionSnapshot.fromJson(const <String, dynamic>{}).themeIndex, 0);
  });

  test('MemorySessionStore 写入后可读、可清空', () async {
    final store = MemorySessionStore();
    await store.write(const SessionSnapshot(
      huaweiToken: 'music-token',
      huaweiUserId: 'sns-1',
    ));
    await store.writeCredentials(
      const HuaweiCredentials(account: 'demo-account', password: 'demo-pass'),
    );

    final restored = await store.read();
    final credentials = await store.readCredentials();

    expect(restored?.huaweiToken, 'music-token');
    expect(restored?.huaweiUserId, 'sns-1');
    expect(credentials?.account, 'demo-account');
    expect(credentials?.password, 'demo-pass');
    await store.clear();
    expect(await store.read(), isNull);
    expect(await store.readCredentials(), isNull);
  });

  test('PreferencesSessionStore 真正落盘：重启后仍能恢复', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final first = PreferencesSessionStore();
    await first.write(const SessionSnapshot(
      source: 'netease',
      huaweiToken: 'music-token',
      neteaseMusicU: 'music-u',
      themeIndex: 5,
    ));

    // 模拟重启：新实例从同一个 SharedPreferences key 读取。
    final second = PreferencesSessionStore();
    final restored = await second.read();

    expect(restored?.source, 'netease');
    expect(restored?.huaweiToken, 'music-token');
    expect(restored?.neteaseMusicU, 'music-u');
    expect(restored?.themeIndex, 5);
  });

  test('PreferencesSessionStore 加密保存凭据且不在 JSON 中出现明文', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const account = 'demo-user@example.com';
    const password = 'S3cret-Passw0rd!';
    final first = PreferencesSessionStore();
    await first.write(const SessionSnapshot(
      huaweiToken: 'music-token',
      huaweiUserId: 'sns-1',
      themeIndex: 4,
    ));
    await first.writeCredentials(
      const HuaweiCredentials(account: account, password: password),
    );

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(PreferencesSessionStore.key) ?? '';
    expect(raw, isNot(contains(password)));
    expect(raw, isNot(contains(account)));
    expect(raw, contains('huaweiAccountEncrypted'));
    expect(raw, contains('credentialKey'));

    final second = PreferencesSessionStore();
    final snapshot = await second.read();
    final credentials = await second.readCredentials();
    expect(snapshot?.huaweiToken, 'music-token');
    expect(snapshot?.themeIndex, 4);
    expect(credentials, const HuaweiCredentials(
      account: account,
      password: password,
    ));

    // 普通会话/设置写入不能覆盖加密凭据。
    await second.write(const SessionSnapshot(
      huaweiToken: 'newer-token',
      huaweiUserId: 'sns-1',
      themeIndex: 5,
    ));
    expect(
      await second.readCredentials(),
      const HuaweiCredentials(account: account, password: password),
    );
    expect((await second.read())?.themeIndex, 5);

    await second.clearCredentials();
    expect(await second.readCredentials(), isNull);
    expect((await second.read())?.huaweiToken, 'newer-token');
    expect(
      (await SharedPreferences.getInstance())
          .getString(PreferencesSessionStore.key),
      isNot(contains(password)),
    );

    await second.clear();
    expect(await second.read(), isNull);
    expect(await second.readCredentials(), isNull);
  });

  test('旧版会话 JSON 缺少设置/凭据字段时安全回落', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferencesSessionStore.key: jsonEncode(<String, dynamic>{
        'source': 'huawei',
        'huaweiToken': 'old-music-token',
        'huaweiUserId': 'old-user',
        'themeIndex': 2,
      }),
    });
    final store = PreferencesSessionStore();
    final snapshot = await store.read();

    expect(snapshot?.huaweiToken, 'old-music-token');
    expect(snapshot?.themeIndex, 2);
    expect(snapshot?.volume, 1.0);
    expect(snapshot?.qualityName, 'hiRes');
    expect(snapshot?.lyricStyleFont, '鸿蒙黑体');
    expect(snapshot?.glassIndex, 1);
    expect(await store.readCredentials(), isNull);
  });
}
