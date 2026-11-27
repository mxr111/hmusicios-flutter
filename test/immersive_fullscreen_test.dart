import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/main.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/services/audio_controller.dart';
import 'package:muyu_flutter/theme.dart';
import 'package:muyu_flutter/widgets/common.dart';
import 'package:muyu_flutter/widgets/immersive_player.dart';
import 'package:muyu_flutter/widgets/player_bar.dart';
import 'package:muyu_flutter/widgets/sidebar.dart';

class _SilentAudioPlayer extends AudioPlayer {
  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {}
}

class _FullscreenState extends AppState {
  _FullscreenState()
    : super(
        audioController: MuyuAudioController(
          HuaweiAPI(),
          player: _SilentAudioPlayer(),
        ),
      );

  int openLyricsCalls = 0;
  int openPlayerCalls = 0;

  @override
  Future<void> showLyricsFor(Song song) async {
    openLyricsCalls++;
    showPlayer = true;
    showLyrics = false;
    refresh();
  }

  @override
  Future<void> openFullPlayer(Song song) async {
    openPlayerCalls++;
    showPlayer = true;
    showLyrics = false;
    refresh();
  }
}

Widget _host(AppState state, {EdgeInsets padding = EdgeInsets.zero}) {
  return MaterialApp(
    theme: MuyuTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(1200, 900),
        padding: padding,
        viewPadding: padding,
        viewInsets: EdgeInsets.zero,
      ),
      child: AnimatedBuilder(
        animation: state,
        builder: (context, _) => AppShell(state: state),
      ),
    ),
  );
}

Widget _immersiveHost(AppState state, Size size) {
  return MaterialApp(
    theme: MuyuTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        padding: const EdgeInsets.only(top: 44, bottom: 34),
        viewPadding: const EdgeInsets.only(top: 44, bottom: 34),
      ),
      child: ImmersivePlayer(state: state),
    ),
  );
}

Song _song() => Song(
  id: 's1',
  name: '晴天',
  artists: const <String>['周杰伦'],
  durationMs: 269000,
);

void main() {
  testWidgets('歌词入口打开同一播放器，默认封面且只有经典样式', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _FullscreenState();
    state.audio.current = _song();

    const topInset = 48.0;
    await tester.pumpWidget(
      _host(state, padding: const EdgeInsets.only(top: topInset, bottom: 34)),
    );
    await tester.pump();

    expect(find.byType(Sidebar), findsOneWidget);
    expect(find.byType(PlayerBar), findsOneWidget);

    await tester.tap(find.byTooltip('歌词'));
    await tester.pump();
    await tester.pump();

    expect(state.openLyricsCalls, 1);
    expect(state.openPlayerCalls, 0);
    expect(state.showPlayer, isTrue);
    expect(state.showLyrics, isFalse);
    expect(state.immersiveFullscreen, isTrue);
    expect(find.byType(Sidebar), findsNothing);
    expect(find.byType(PlayerBar), findsNothing);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(ImmersivePlayer), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('immersive-stage-classic')),
      findsOneWidget,
    );

    // 退出沉浸后仍停留在封面页，不再出现皮肤/歌词页切换按钮。
    await tester.tap(find.byTooltip('退出全屏沉浸'));
    await tester.pump();
    expect(find.byTooltip('全屏沉浸'), findsOneWidget);
    expect(find.byTooltip('歌词样式'), findsOneWidget);
    expect(find.byTooltip('音质与音效'), findsOneWidget);
    expect(find.byTooltip('播放器样式'), findsNothing);
    expect(find.byTooltip('歌词页'), findsNothing);
    expect(find.byTooltip('封面播放页'), findsNothing);
    expect(find.byIcon(Icons.style_outlined), findsNothing);
    expect(find.text('播放器样式'), findsNothing);

    // 顶部退出键必须落在系统状态栏安全区下方。
    await tester.tap(find.byTooltip('全屏沉浸'));
    await tester.pump();
    final exitRect = tester.getRect(find.byTooltip('退出全屏播放'));
    expect(exitRect.top, greaterThanOrEqualTo(topInset));

    await tester.tap(find.byTooltip('退出全屏播放'));
    await tester.pump();
    expect(state.showPlayer, isFalse);
    expect(state.showLyrics, isFalse);
    expect(state.immersiveFullscreen, isFalse);
    expect(find.byType(Sidebar), findsOneWidget);
    expect(find.byType(PlayerBar), findsOneWidget);
    state.dispose();
  });

  testWidgets('播放条封面进入经典播放器并可切换全屏沉浸', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _FullscreenState();
    state.audio.current = _song();
    await tester.pumpWidget(_host(state));
    await tester.pump();

    await tester.tap(find.byType(VinylCover).first);
    await tester.pump();
    await tester.pump();
    expect(state.openPlayerCalls, 1);
    expect(state.openLyricsCalls, 0);
    expect(state.showPlayer, isTrue);
    expect(state.showLyrics, isFalse);
    expect(find.byType(Sidebar), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('immersive-stage-classic')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('全屏沉浸'));
    await tester.pump();
    expect(state.immersiveFullscreen, isTrue);
    expect(find.byType(Sidebar), findsNothing);
    state.dispose();
  });

  testWidgets('竖屏默认封面，点封面/左右滑动切换歌词页，音量滑块可调', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _FullscreenState();
    state.audio.current = _song();
    await tester.pumpWidget(_immersiveHost(state, const Size(390, 844)));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('immersive-portrait-pages')),
      findsOneWidget,
    );
    expect(find.text('封面 · 轻点封面或右滑查看歌词'), findsOneWidget);
    expect(find.byTooltip('播放器样式'), findsNothing);
    expect(find.byTooltip('歌词页'), findsNothing);
    expect(find.byTooltip('封面播放页'), findsNothing);

    await tester.tap(find.byType(VinylCover).first);
    await tester.pumpAndSettle();
    expect(find.text('歌词 · 左滑返回封面'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(360, 0));
    await tester.pumpAndSettle();
    expect(find.text('封面 · 轻点封面或右滑查看歌词'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-360, 0));
    await tester.pumpAndSettle();
    expect(find.text('歌词 · 左滑返回封面'), findsOneWidget);

    await tester.tap(find.byTooltip('音量'));
    await tester.pumpAndSettle();
    final volumeSlider = find.byKey(const ValueKey<String>('volume-slider'));
    expect(volumeSlider, findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('volume-percent')),
      findsOneWidget,
    );

    final revisionBefore = state.audio.settingsRevision.value;
    tester.widget<Slider>(volumeSlider).onChanged!(0.37);
    await tester.pump();
    expect(state.audio.volume, closeTo(0.37, 0.001));
    expect(state.audio.settingsRevision.value, greaterThan(revisionBefore));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('volume-percent')))
          .data,
      '37%',
    );

    await tester.tap(find.byTooltip('静音'));
    await tester.pump();
    expect(state.audio.volume, 0);
    expect(find.byTooltip('取消静音'), findsOneWidget);
    state.dispose();
  });

  testWidgets('窄屏进入全屏后底部标签栏也隐藏，退出恢复', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _FullscreenState();
    state.audio.current = _song();
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 44, bottom: 34),
            viewPadding: EdgeInsets.only(top: 44, bottom: 34),
          ),
          child: AnimatedBuilder(
            animation: state,
            builder: (context, _) => AppShell(state: state),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(BottomNavigationBar), findsOneWidget);

    await tester.tap(find.byType(VinylCover).first);
    await tester.pump();
    await tester.pump();
    expect(state.showPlayer, isTrue);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(PlayerBar), findsNothing);
    expect(find.byType(PageView), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pump();
    expect(state.showPlayer, isFalse);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    state.dispose();
  });

  testWidgets('根布局 SafeArea 不让自定义账号头压住系统状态栏', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _FullscreenState();

    const topInset = 48.0;
    await tester.pumpWidget(
      _host(state, padding: const EdgeInsets.only(top: topInset)),
    );
    await tester.pump();

    final header = tester.getRect(find.text('登录华为音乐'));
    expect(header.top, greaterThanOrEqualTo(topInset));
    state.dispose();
  });
}
