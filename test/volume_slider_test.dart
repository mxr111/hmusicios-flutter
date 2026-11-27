import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/services/audio_controller.dart';
import 'package:muyu_flutter/theme.dart';
import 'package:muyu_flutter/widgets/immersive_player.dart';
import 'package:muyu_flutter/widgets/player_bar.dart';

class _SilentPlayer extends AudioPlayer {
  @override
  Future<void> setVolume(double volume) async {}

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
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

AppState _state() => AppState(
  audioController: MuyuAudioController(HuaweiAPI(), player: _SilentPlayer()),
);

Song _song() => Song(
  id: 'volume-song',
  name: '音量测试',
  artists: const <String>['测试歌手'],
  durationMs: 180000,
);

void main() {
  testWidgets('沉浸播放器音量滑块调整音量且不会误触静音', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _state();
    addTearDown(state.dispose);
    state.audio.current = _song();

    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1200, 900)),
          child: Scaffold(body: ImmersivePlayer(state: state)),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('音量'));
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey<String>('volume-slider'));
    expect(slider, findsOneWidget);

    tester.widget<Slider>(slider).onChanged!(0.42);
    await tester.pump();
    expect(state.audio.volume, closeTo(0.42, 0.001));
    expect(state.audio.volume, greaterThan(0));
    expect(state.audio.settingsRevision.value, greaterThan(0));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('volume-percent')))
          .data,
      '42%',
    );

    await tester.tap(find.byTooltip('静音'));
    await tester.pump();
    expect(state.audio.volume, 0);
    expect(find.byTooltip('取消静音'), findsOneWidget);

    await tester.tap(find.byTooltip('取消静音'));
    await tester.pump();
    expect(state.audio.volume, 1);
  });

  testWidgets('播放条音量对话框同样走 AppState 并即时刷新百分比', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _state();
    addTearDown(state.dispose);
    state.audio.current = _song();

    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1200, 900)),
          child: Scaffold(
            body: Center(
              child: SizedBox(width: 1000, child: PlayerBar(state: state)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('音量'));
    await tester.pumpAndSettle();
    final slider = find.byKey(
      const ValueKey<String>('player-bar-volume-slider'),
    );
    expect(slider, findsOneWidget);

    tester.widget<Slider>(slider).onChanged!(0.25);
    await tester.pump();
    expect(state.audio.volume, closeTo(0.25, 0.001));
    expect(find.text('25%'), findsOneWidget);
  });
}
