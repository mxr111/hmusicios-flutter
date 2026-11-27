import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/services/audio_controller.dart';
import 'package:muyu_flutter/services/session_store.dart';

class _SkipApi extends HuaweiAPI {
  _SkipApi() : super(gateway: HuaweiGateway());

  int audioCalls = 0;

  @override
  Future<List<HuaweiAudioFile>> audioFiles(
    String songCode, {
    Set<AudioQuality>? upstreamQualities,
  }) async {
    audioCalls++;
    if (songCode == 'vip-only') {
      throw const HuaweiException(
        '华为取流失败（歌曲 vip-only，码 142411，最终档位 standard/1）：'
        '超级钻石 VIP 专享，当前账号无播放权限',
      );
    }
    return <HuaweiAudioFile>[
      HuaweiAudioFile(
        quality: AudioQuality.standard,
        qualityType: '1',
        url: Uri.parse(
          'https://test.dbankcdn.cn/ok-MP3-128K-FTD.mp3',
        ),
        sizeBytes: 4332025,
      ),
    ];
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

class _AuthFailGateway extends HuaweiGateway {
  final List<String> requestedTypes = <String>[];

  @override
  Future<Map<String, dynamic>> request(String path,
      {Map<String, dynamic> body = const <String, dynamic>{}}) async {
    requestedTypes.add('${body['qualityType']}');
    throw HuaweiBusinessException('990000', '鉴权失败');
  }
}

/// 不覆写 audioFiles，确保走真实的取流降档 / 鉴权中止逻辑。
class _AuthFailApi extends HuaweiAPI {
  _AuthFailApi(this.authGateway) : super(gateway: authGateway);

  final _AuthFailGateway authGateway;

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

class _FakeAudio extends MuyuAudioController {
  _FakeAudio(super.api);

  final List<String> played = <String>[];

  @override
  Future<void> playSong(Song song, {List<Song>? list}) async {
    if (list != null && list.isNotEmpty) {
      queue = List<Song>.of(list);
      index = queue.indexWhere((item) => item.id == song.id);
      if (index < 0) {
        queue.insert(0, song);
        index = 0;
      }
    }
    played.add(song.id);
    current = song;
    error = song.id == 'vip-only'
        ? '华为取流失败（歌曲 vip-only，码 142411，最终档位 standard/1）：'
              '超级钻石 VIP 专享，当前账号无播放权限'
        : null;
    notifyListeners();
  }
}

class _ApiBackedAudio extends MuyuAudioController {
  _ApiBackedAudio(super.api);

  final List<String> played = <String>[];

  @override
  Future<void> playSong(Song song, {List<Song>? list}) async {
    if (list != null && list.isNotEmpty) {
      queue = List<Song>.of(list);
      index = queue.indexWhere((item) => item.id == song.id);
      if (index < 0) {
        queue.insert(0, song);
        index = 0;
      }
    }
    played.add(song.id);
    current = song;
    try {
      await api.audioFiles(song.id, upstreamQualities: song.qualities);
      error = null;
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }
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

  test('142411 / super diamond vip 被识别为可跳过错误', () {
    expect(
      AppState.looksUnplayable(
        '华为取流失败（歌曲 110745494，码 142411，最终档位 standard/1）：'
        '超级钻石 VIP 专享，当前账号无播放权限',
      ),
      isTrue,
    );
    expect(
      AppState.looksUnplayable(
        'Only super diamond vip user can play the content!',
      ),
      isTrue,
    );
    expect(AppState.looksUnplayable('网络请求失败：timeout'), isFalse);
  });

  test('普通点歌会清空电台续播回调，避免歌单尾部误续私人电台', () async {
    final api = _SkipApi();
    final audio = _FakeAudio(api);
    final state = AppState(
      sessionStore: MemorySessionStore(),
      huaweiApi: api,
      audioController: audio,
    );
    audio.onQueueExhausted = () async => <Song>[];
    final song = Song(id: 'normal', name: '普通歌曲');

    await state.play(song, queue: <Song>[song]);

    expect(audio.onQueueExhausted, isNull);
    expect(state.error, isNull);
    state.dispose();
  });

  test('真 VIP 全档失败时 play 自动尝试队列下一首', () async {
    final api = _SkipApi();
    final audio = _FakeAudio(api);
    final state = AppState(
      sessionStore: MemorySessionStore(),
      huaweiApi: api,
      audioController: audio,
    );
    final vip = Song(id: 'vip-only', name: '真 VIP 歌');
    final playable = Song(id: 'playable', name: '可播放歌曲');

    await state.play(vip, queue: <Song>[vip, playable]);

    expect(audio.played, <String>['vip-only', 'playable']);
    expect(state.audio.current?.id, 'playable');
    expect(state.error, isNull);
    state.dispose();
  });

  test('990000 鉴权失败不跳下一首，最终错误要求重新登录', () async {
    final api = _AuthFailApi(_AuthFailGateway());
    final audio = _ApiBackedAudio(api);
    final state = AppState(
      sessionStore: MemorySessionStore(),
      huaweiApi: api,
      audioController: audio,
    );
    final expired = Song(id: 'auth-expired', name: '鉴权失效歌');
    final playable = Song(id: 'playable', name: '可播放歌曲');

    await state.play(expired, queue: <Song>[expired, playable]);

    expect(audio.played, <String>['auth-expired']);
    expect(state.audio.current?.id, 'auth-expired');
    expect(api.authGateway.requestedTypes, isNotEmpty);
    expect(state.error, contains('990000'));
    expect(state.error, contains('重新登录'));
    expect(AppState.looksUnplayable(state.error), isFalse);
    state.dispose();
  });
}
