import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/services/audio_controller.dart';
import 'package:muyu_flutter/theme.dart';
import 'package:muyu_flutter/widgets/common.dart';
import 'package:muyu_flutter/widgets/immersive_player.dart';

class _SilentPlayer extends AudioPlayer {
  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {}

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

Song _song(String id) => Song(
  id: id,
  name: '歌曲 $id',
  artists: const <String>['测试歌手'],
  localPath: 'C:/tmp/$id.mp3',
  durationMs: 180000,
);

Widget _host(AppState state) => MaterialApp(
  theme: MuyuTheme.light(),
  home: MediaQuery(
    data: const MediaQueryData(size: Size(1200, 900)),
    child: Scaffold(body: ImmersivePlayer(state: state)),
  ),
);

void main() {
  testWidgets('切歌、改设置和调 offset 都会推进歌词/设置版本', (tester) async {
    final audio = MuyuAudioController(HuaweiAPI(), player: _SilentPlayer());
    addTearDown(audio.dispose);

    await audio.playSong(_song('a'), list: <Song>[_song('a')]);
    expect(audio.lyricRevision.value, 1);

    await audio.playSong(_song('b'), list: <Song>[_song('b')]);
    expect(audio.lyricRevision.value, 2);

    await audio.seek(const Duration(seconds: 10));
    final lyricBefore = audio.lyricRevision.value;
    final settingsBefore = audio.settingsRevision.value;
    await audio.setLyricOffset(const Duration(milliseconds: 120));
    expect(audio.lyricRevision.value, lyricBefore + 1);
    expect(audio.settingsRevision.value, settingsBefore + 1);
    expect(
      audio.lyricPosition.inMicroseconds,
      closeTo(
        const Duration(seconds: 10, milliseconds: 120).inMicroseconds,
        5000,
      ),
    );

    await audio.setVolume(0.4);
    expect(audio.settingsRevision.value, settingsBefore + 2);
    expect(audio.volume, closeTo(0.4, 0.001));

    audio.setEffect('清晰增强');
    expect(audio.settingsRevision.value, settingsBefore + 3);
    audio.setEffect('不存在的音效');
    expect(audio.settingsRevision.value, settingsBefore + 3);
    expect(audio.effect, '清晰增强');
  });

  testWidgets('AppState 歌词版本变化会重建 LyricFocusList key', (tester) async {
    final audio = MuyuAudioController(HuaweiAPI(), player: _SilentPlayer());
    final state = AppState(audioController: audio);
    addTearDown(state.dispose);
    state.audio.current = _song('a');
    state.lyrics = <LyricLine>[
      const LyricLine(Duration.zero, '第一句'),
      const LyricLine(Duration(seconds: 3), '第二句'),
      const LyricLine(Duration(seconds: 6), '第三句'),
    ];

    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    final before = tester.widget<LyricFocusList>(find.byType(LyricFocusList));
    expect(before.songId, 'a');

    state.bumpLyricsRevision();
    await tester.pump();
    final after = tester.widget<LyricFocusList>(find.byType(LyricFocusList));
    expect(after.key, isNot(before.key));
  });

  testWidgets('调歌词 offset 后界面版本立即推进且 lyricPosition 叠加偏移', (tester) async {
    final audio = MuyuAudioController(HuaweiAPI(), player: _SilentPlayer());
    final state = AppState(audioController: audio);
    addTearDown(state.dispose);
    state.audio.current = _song('a');
    await tester.pumpWidget(_host(state));
    await tester.pump();

    final before = state.lyricsRevision.value;
    state.setLyricOffset(const Duration(milliseconds: 150));
    await tester.pump();
    expect(state.lyricsRevision.value, greaterThan(before));
    expect(state.audio.lyricPosition, const Duration(milliseconds: 150));
  });

  testWidgets('竖屏默认封面，点封面进歌词页并可水平滑回', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final audio = MuyuAudioController(HuaweiAPI(), player: _SilentPlayer());
    final state = AppState(audioController: audio);
    addTearDown(state.dispose);
    state.audio.current = _song('a');

    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 44, bottom: 34),
            viewPadding: EdgeInsets.only(top: 44, bottom: 34),
          ),
          child: ImmersivePlayer(state: state),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('封面 · 轻点封面或右滑查看歌词'), findsOneWidget);

    await tester.tap(find.byType(VinylCover).first);
    await tester.pumpAndSettle();
    expect(find.text('歌词 · 左滑返回封面'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(360, 0));
    await tester.pumpAndSettle();
    expect(find.text('封面 · 轻点封面或右滑查看歌词'), findsOneWidget);
  });
}
