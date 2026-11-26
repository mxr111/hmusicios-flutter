import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/services/session_store.dart';

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
}
