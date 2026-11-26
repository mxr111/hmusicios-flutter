import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/services/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGateway extends HuaweiGateway {}

class _FakeHuaweiAPI extends HuaweiAPI {
  _FakeHuaweiAPI({this.failFirst = false}) : super(gateway: _FakeGateway());

  bool failFirst;
  int discoverCalls = 0;

  @override
  Future<DiscoverData> discover() async {
    discoverCalls++;
    if (failFirst && discoverCalls == 1) {
      throw const HuaweiException('华为鉴权失败，请重新登录华为账号');
    }
    Song song(String id) =>
        Song(id: id, name: id, artists: const <String>['真实歌手']);
    return DiscoverData(
      listen: <Song>[song('listen-1')],
      daily: <Song>[song('daily-1')],
      heart: <Song>[song('heart-1')],
      newSongs: <Song>[song('new-1')],
      hot: <Song>[song('hot-1')],
      recommended: <Song>[song('rec-1')],
      playlists: const <Playlist>[
        Playlist(id: 'a001', name: '每日30首', kind: 'collected'),
        Playlist(id: 'pl-1', name: '推荐歌单一', kind: 'collected'),
      ],
      charts: const <Playlist>[
        Playlist(id: '24926', name: '热歌榜', kind: 'chart'),
      ],
      recommendedColumnId: '8011',
    );
  }

  @override
  void signInWithToken(String token, {String? nick}) {
    gateway.session = MusicSession(token: token, snsUserId: 'user');
  }

  @override
  Future<void> refreshProfile() async {}

  @override
  Future<List<Song>> favorites({
    int start = 0,
    int limit = 50,
    bool fetchAll = true,
  }) async => const <Song>[];

  @override
  Future<List<Playlist>> playlists() async => const <Playlist>[];
}

class _RestoreGateway extends HuaweiGateway {
  int exchangeCalls = 0;
  String? exchangeAccountToken;
  bool failExchange = false;

  @override
  Future<MusicSession> exchangeMusicToken(String accessToken) async {
    exchangeCalls++;
    exchangeAccountToken = accessToken;
    if (failExchange) {
      throw const HuaweiException('990006 User token expired!');
    }
    final updated = MusicSession(
      token: 'new-music-token',
      snsUserId: 'user',
      expireTime: DateTime.now()
          .add(const Duration(hours: 2))
          .toUtc()
          .toIso8601String(),
    );
    session = updated;
    accountToken = accessToken;
    return updated;
  }
}

class _RestoreAPI extends HuaweiAPI {
  _RestoreAPI(_RestoreGateway gateway) : super(gateway: gateway);

  @override
  Future<void> refreshProfile() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async => 0,
    );
    messenger.setMockStreamHandler(
      const EventChannel('xyz.luan/audioplayers.global/events'),
      MockStreamHandler.inline(onListen: (args, sink) {}),
    );
    messenger.setMockStreamHandler(
      const EventChannel('xyz.luan/audioplayers.events'),
      MockStreamHandler.inline(onListen: (args, sink) {}),
    );
  });

  test('loadHome 使用 discover 的独立字段，不再跨卡片复用', () async {
    final api = _FakeHuaweiAPI();
    final state = AppState(sessionStore: MemorySessionStore(), huaweiApi: api);

    await state.loadHome();
    expect(state.discoverLoaded, isTrue);
    expect(state.discover.listen.single.id, 'listen-1');
    expect(state.discover.daily.single.id, 'daily-1');
    expect(state.discover.heart.single.id, 'heart-1');
    expect(state.discover.newSongs.single.id, 'new-1');
    expect(state.discover.hot.single.id, 'hot-1');
    expect(state.discover.recommended.single.id, 'rec-1');
    // homeSongs 只作为全局默认播放入口，不再把所有卡片拼在一起。
    expect(state.homeSongs.single.id, 'rec-1');
    state.dispose();
  });

  test('990000 冷却后普通加载被挡住，force 刷新可恢复', () async {
    final api = _FakeHuaweiAPI(failFirst: true);
    final state = AppState(sessionStore: MemorySessionStore(), huaweiApi: api);

    await state.loadHome();
    expect(state.error, contains('重新登录'));
    expect(api.discoverCalls, 1);
    expect(state.discoverLoaded, isFalse);

    await state.loadHome();
    expect(api.discoverCalls, 1, reason: '30 秒冷却内普通加载应直接返回');

    await state.refreshHome(force: true);
    expect(api.discoverCalls, 2);
    expect(state.discoverLoaded, isTrue);
    state.dispose();
  });

  test('登录成功走 refreshHome(force: true)，不受冷却影响', () async {
    final api = _FakeHuaweiAPI(failFirst: true);
    final state = AppState(sessionStore: MemorySessionStore(), huaweiApi: api);
    await state.loadHome();
    expect(api.discoverCalls, 1);

    state.signInWithToken('login-token');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(api.discoverCalls, 2);
    expect(state.discoverLoaded, isTrue);
    state.dispose();
  });

  test('连续 force 刷新被合并/抑制，不排队重跑完整首页', () async {
    final api = _FakeHuaweiAPI();
    final state = AppState(sessionStore: MemorySessionStore(), huaweiApi: api);
    await state.loadHome();
    expect(api.discoverCalls, 1);

    await Future.wait(<Future<void>>[
      for (var i = 0; i < 5; i++) state.refreshHome(force: true),
    ]);

    expect(api.discoverCalls, lessThanOrEqualTo(2));
    expect(state.suppressedHomeRefreshes, greaterThan(0));
    state.dispose();
  });

  test('restoreSession 单独保存 refreshToken，过期时用账号 token 刷新', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final gateway = _RestoreGateway();
    final api = _RestoreAPI(gateway);
    final store = MemorySessionStore();
    await store.write(
      const SessionSnapshot(
        huaweiToken: 'old-music-token',
        huaweiUserId: 'user',
        huaweiAccountToken: 'account-token',
        huaweiRefreshToken: 'real-refresh-token',
        huaweiExpireTime: '2020-01-01T00:00:00Z',
      ),
    );
    final state = AppState(sessionStore: store, huaweiApi: api);

    await state.restoreSession();

    expect(gateway.refreshToken, 'real-refresh-token');
    expect(gateway.refreshToken, isNot('account-token'));
    expect(gateway.exchangeCalls, 1);
    expect(gateway.exchangeAccountToken, 'account-token');
    expect(api.isLoggedIn, isTrue);
    expect(state.error, isNull);
    state.dispose();
  });

  test('restoreSession 过期且刷新失败时要求重新登录', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final gateway = _RestoreGateway()..failExchange = true;
    final api = _RestoreAPI(gateway);
    final store = MemorySessionStore();
    await store.write(
      const SessionSnapshot(
        huaweiToken: 'old-music-token',
        huaweiUserId: 'user',
        huaweiAccountToken: 'account-token',
        huaweiExpireTime: '2020-01-01T00:00:00Z',
      ),
    );
    final state = AppState(sessionStore: store, huaweiApi: api);

    await state.restoreSession();

    expect(gateway.exchangeCalls, 1);
    expect(api.isLoggedIn, isFalse);
    expect(state.error, contains('重新扫码登录'));
    state.dispose();
  });
}
