import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/services/audio_controller.dart';
import 'package:muyu_flutter/services/session_store.dart';

class _NoopPlayer extends AudioPlayer {
  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() async {}
}

/// 心动首屏走 heartFmFirstPage；只有续页才走 privateFmPage。
class _HeartApi extends HuaweiAPI {
  _HeartApi({this.moreAfterFirst = true})
    : super(gateway: HuaweiGateway());

  final bool moreAfterFirst;
  final List<Map<String, String>> privateFmRequests =
      <Map<String, String>>[];
  final List<String> requestedNext = <String>[];
  int heartFmCalls = 0;
  int calls = 0;

  Song song(String id) => Song(
    id: id,
    name: id,
    qualities: const <AudioQuality>{AudioQuality.standard},
  );

  @override
  Future<HuaweiPrivateFmPage> heartFmFirstPage({String refInfo = ''}) async {
    heartFmCalls++;
    return HuaweiPrivateFmPage(
      songs: <Song>[song('heart-1'), song('heart-2')],
      next: moreAfterFirst ? 'heart-cursor-1' : '',
      more: moreAfterFirst,
      refInfo: moreAfterFirst ? 'heart-ref-1' : '',
      rcmScenario: '21',
      mode: '1',
    );
  }

  @override
  Future<HuaweiPrivateFmPage> privateFmPage({
    String mode = '1',
    String rcmScenario = '16',
    String refInfo = '',
    String next = '',
  }) async {
    calls++;
    requestedNext.add(next);
    privateFmRequests.add(<String, String>{
      'mode': mode,
      'rcmScenario': rcmScenario,
      'refInfo': refInfo,
      'next': next,
    });
    return HuaweiPrivateFmPage(
      songs: <Song>[song('heart-2'), song('heart-3')],
      next: '',
      more: false,
      refInfo: refInfo,
      rcmScenario: rcmScenario,
      mode: mode,
    );
  }
}

class _FakeAudio extends MuyuAudioController {
  _FakeAudio(super.api) : super(player: _NoopPlayer());

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
    } else {
      final found = queue.indexWhere((item) => item.id == song.id);
      if (found >= 0) index = found;
    }
    played.add(song.id);
    current = song;
    error = null;
    notifyListeners();
  }

  @override
  Future<void> stop() async {}
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

  test('心动续页追加到 discover.heart，不写入 discover.listen', () async {
    final api = _HeartApi();
    final audio = _FakeAudio(api);
    final state = AppState(
      sessionStore: MemorySessionStore(),
      huaweiApi: api,
      audioController: audio,
    );

    await state.playCard('heart');
    expect(api.heartFmCalls, 1);
    expect(api.privateFmRequests, isEmpty);
    expect(state.discover.heart.map((song) => song.id).toList(), <String>[
      'heart-1',
      'heart-2',
    ]);
    expect(state.discover.listen, isEmpty);
    expect(state.radioNext, 'heart-cursor-1');
    expect(state.radioMore, isTrue);
    expect(state.radioRefInfo, 'heart-ref-1');
    expect(audio.queue.map((song) => song.id).toList(), <String>[
      'heart-1',
      'heart-2',
    ]);
    expect(audio.current?.id, 'heart-1');

    await audio.next();
    expect(audio.current?.id, 'heart-2');
    expect(api.requestedNext, isEmpty);

    await audio.next();

    expect(api.requestedNext, <String>['heart-cursor-1']);
    expect(api.privateFmRequests.single['mode'], '1');
    expect(api.privateFmRequests.single['rcmScenario'], '16');
    expect(api.privateFmRequests.single['refInfo'], 'heart-ref-1');
    expect(audio.queue.map((song) => song.id).toList(), <String>[
      'heart-1',
      'heart-2',
      'heart-3',
    ]);
    expect(audio.current?.id, 'heart-3');
    expect(state.discover.heart.map((song) => song.id).toList(), <String>[
      'heart-1',
      'heart-2',
      'heart-3',
    ]);
    expect(state.discover.listen, isEmpty);
    expect(state.radioMore, isFalse);
    expect(audio.error, isNull);
    state.dispose();
  });

  test('more=false 时心动队列播到尾部不请求续页，按列表循环回到首曲', () async {
    final api = _HeartApi(moreAfterFirst: false);
    final audio = _FakeAudio(api);
    final state = AppState(
      sessionStore: MemorySessionStore(),
      huaweiApi: api,
      audioController: audio,
    );

    await state.playCard('heart');
    await audio.next();
    await audio.next();

    expect(api.requestedNext, isEmpty);
    expect(api.calls, 0);
    expect(audio.current?.id, 'heart-1');
    expect(audio.queue.length, 2);
    state.dispose();
  });

  test('普通点歌会清空心动续播回调，播完不再请求 privatefm', () async {
    final api = _HeartApi();
    final audio = _FakeAudio(api);
    final state = AppState(
      sessionStore: MemorySessionStore(),
      huaweiApi: api,
      audioController: audio,
    );

    await state.playCard('heart');
    expect(audio.onQueueExhausted, isNotNull);

    final other = api.song('other');
    await state.play(other, queue: <Song>[other]);

    expect(audio.onQueueExhausted, isNull);
    expect(audio.current?.id, 'other');
    expect(api.calls, 0);
    state.dispose();
  });
}
