import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/main.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/models_skin.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/theme.dart';
import 'package:muyu_flutter/widgets/common.dart';
import 'package:muyu_flutter/widgets/immersive_player.dart';
import 'package:muyu_flutter/widgets/player_bar.dart';
import 'package:muyu_flutter/widgets/sidebar.dart';

class _FullscreenState extends AppState {
  int openLyricsCalls = 0;
  int openPlayerCalls = 0;

  @override
  Future<void> showLyricsFor(Song song) async {
    openLyricsCalls++;
    showPlayer = true;
    showLyrics = true;
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

Song _song() => Song(
  id: 's1',
  name: '晴天',
  artists: const <String>['周杰伦'],
  durationMs: 269000,
);

void main() {
  testWidgets('歌词按钮进入全屏：隐藏外围 UI，只保留当前 player style', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _FullscreenState();
    state.setPlayerStyle(PlayerStyle.classic);
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
    expect(state.showPlayer, isTrue);
    expect(state.showLyrics, isTrue);
    expect(state.immersiveFullscreen, isTrue);
    expect(find.byType(Sidebar), findsNothing);
    expect(find.byType(PlayerBar), findsNothing);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(ImmersivePlayer), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('immersive-stage-classic')),
      findsOneWidget,
    );

    for (final style in PlayerStyle.values) {
      state.setPlayerStyle(style);
      await tester.pump();
      expect(
        find.byKey(ValueKey<String>('immersive-stage-${style.name}')),
        findsOneWidget,
      );
    }

    // 顶部退出键必须落在系统状态栏安全区下方。
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

  testWidgets('播放条封面/空白与全屏按钮进入同一个应用级全屏播放器', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _FullscreenState();
    state.setPlayerStyle(PlayerStyle.cover);
    state.audio.current = _song();
    await tester.pumpWidget(_host(state));
    await tester.pump();

    await tester.tap(find.byType(VinylCover).first);
    await tester.pump();
    await tester.pump();
    expect(state.openPlayerCalls, 1);
    expect(find.byType(Sidebar), findsNothing);
    expect(find.byType(PlayerBar), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('immersive-stage-cover')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('全屏沉浸'));
    await tester.pump();
    expect(state.immersiveFullscreen, isTrue);
    expect(
      find.byKey(const ValueKey<String>('immersive-stage-cover')),
      findsOneWidget,
    );
    expect(find.byType(Sidebar), findsNothing);
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
