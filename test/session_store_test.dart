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

    final restored = await store.read();

    expect(restored?.huaweiToken, 'music-token');
    expect(restored?.huaweiUserId, 'sns-1');
    await store.clear();
    expect(await store.read(), isNull);
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
}
