import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';
import 'package:muyu_flutter/services/audio_controller.dart';

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

class _FailingAudio extends MuyuAudioController {
  _FailingAudio(super.api, this.failing) : super(player: _NoopPlayer());

  final Set<String> failing;
  final List<String> played = <String>[];
  int stops = 0;

  @override
  Future<void> playSong(Song song, {List<Song>? list}) async {
    if (list != null && list.isNotEmpty) {
      queue = List<Song>.of(list);
      index = queue.indexWhere((item) => item.id == song.id);
    } else {
      final found = queue.indexWhere((item) => item.id == song.id);
      if (found >= 0) index = found;
    }
    played.add(song.id);
    current = song;
    error = failing.contains(song.id) ? '取流失败：${song.id}' : null;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

Song _song(int index) => Song(
  id: 'song-$index',
  name: '歌曲 $index',
  qualities: const <AudioQuality>{AudioQuality.standard},
);

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

  test('下一首失败会自动向后继续，成功即停止', () async {
    final api = HuaweiAPI(gateway: HuaweiGateway());
    final audio = _FailingAudio(api, <String>{'song-1', 'song-2', 'song-3'});
    final songs = <Song>[for (var i = 0; i < 8; i++) _song(i)];

    await audio.playSong(songs.first, list: songs);
    await audio.next();

    expect(audio.played, <String>[
      'song-0',
      'song-1',
      'song-2',
      'song-3',
      'song-4',
    ]);
    expect(audio.stops, 3);
    expect(audio.current?.id, 'song-4');
    expect(audio.error, isNull);
    audio.dispose();
  });

  test('连续失败最多尝试 5 首，保留最后一首可读错误', () async {
    final api = HuaweiAPI(gateway: HuaweiGateway());
    final audio = _FailingAudio(
      api,
      <String>{'song-1', 'song-2', 'song-3', 'song-4', 'song-5'},
    );
    final songs = <Song>[for (var i = 0; i < 8; i++) _song(i)];

    await audio.playSong(songs.first, list: songs);
    await audio.next();

    expect(audio.played, <String>[
      'song-0',
      'song-1',
      'song-2',
      'song-3',
      'song-4',
      'song-5',
    ]);
    expect(audio.played, isNot(contains('song-6')));
    expect(audio.stops, 5);
    expect(audio.current?.id, 'song-5');
    expect(audio.error, '取流失败：song-5');
    audio.dispose();
  });
}
