// UI 冒烟测试：在真实 Flutter widget 树里构建发现页与沉浸播放器，
// 提前抓 analyze 发现不了的运行时构建错误（布局溢出、空数据、null 访问）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/models_skin.dart';
import 'package:muyu_flutter/pages/secondary_pages.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/theme.dart';
import 'package:muyu_flutter/widgets/discover_page.dart';
import 'package:muyu_flutter/widgets/common.dart';
import 'package:muyu_flutter/widgets/home_page.dart';
import 'package:muyu_flutter/widgets/immersive_player.dart';

void main() {
  testWidgets('音乐厅在空数据下可构建（推荐歌单/华为榜单）', (tester) async {
    final state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: DiscoverPage(state: state)),
      ),
    );
    await tester.pump();

    expect(find.text('音乐厅'), findsOneWidget);
    expect(find.text('推荐歌单'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('华为音乐榜单'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('华为音乐榜单'), findsOneWidget);
    state.dispose();
  });

  testWidgets('华为音乐主页在空数据下可构建（华为推荐模块）', (tester) async {
    final state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: HomePage(state: state)),
      ),
    );
    await tester.pump();

    expect(find.text('主页'), findsOneWidget);
    expect(find.text('华为音乐'), findsOneWidget);
    expect(find.text('为你推荐'), findsOneWidget);
    expect(find.text('推荐歌单'), findsOneWidget);
    expect(tester.takeException(), isNull);
    state.dispose();
  });

  testWidgets('沉浸播放器在空数据下可构建（无歌词提示 + 播控）', (tester) async {
    final state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: ImmersivePlayer(state: state)),
      ),
    );
    await tester.pump();

    // 经典样式：宽屏默认左封面右歌词，竖屏默认封面页。
    expect(find.text('正在播放'), findsOneWidget);
    expect(find.textContaining('暂无歌词'), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    expect(find.byTooltip('播放器样式'), findsNothing);
    expect(find.byTooltip('歌词页'), findsNothing);
    expect(find.byTooltip('封面播放页'), findsNothing);
    state.dispose();
  });

  testWidgets('播放器只保留经典样式且空数据可构建', (tester) async {
    final state = AppState();
    state.setPlayerStyle(PlayerStyle.classic);
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: ImmersivePlayer(state: state)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('immersive-stage-classic')),
      findsOneWidget,
    );
    expect(find.byTooltip('播放器样式'), findsNothing);
    expect(find.byIcon(Icons.style_outlined), findsNothing);
    state.dispose();
  });

  testWidgets('黑胶封面播放时有旋转且动画随时间推进', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: VinylCover(spinning: true))),
      ),
    );

    final rotation = find.descendant(
      of: find.byType(VinylCover),
      matching: find.byType(RotationTransition),
    );
    final before = tester.widget<RotationTransition>(rotation).turns.value;
    await tester.pump(const Duration(milliseconds: 500));
    final after = tester.widget<RotationTransition>(rotation).turns.value;

    expect(after, isNot(before));
  });

  testWidgets('歌词样式面板支持 +100ms 同步校准', (tester) async {
    final state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: ImmersivePlayer(state: state)),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('歌词样式'));
    await tester.pumpAndSettle();
    expect(find.text('歌词同步'), findsOneWidget);
    expect(state.audio.lyricOffset, Duration.zero);

    await tester.ensureVisible(find.byTooltip('歌词提前 100ms'));
    await tester.tap(find.byTooltip('歌词提前 100ms'));
    await tester.pump();

    expect(state.audio.lyricOffset, const Duration(milliseconds: 100));
    expect(find.textContaining('当前偏移 +100 ms'), findsOneWidget);
    state.dispose();
  });

  testWidgets('皮肤外观页可构建且展示 12 款主题', (tester) async {
    final state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: AppearancePage(state: state),
      ),
    );
    await tester.pump();
    expect(find.text('皮肤与外观'), findsOneWidget);
    // 12 主题色板在 GridView 里（shrinkWrap，全部已构建）。
    for (final p in kMuyuPalettes) {
      expect(find.text(p.label), findsOneWidget, reason: '缺少主题 ${p.label}');
    }
    // 歌词样式与沉浸光感在 ListView 下方，滚动后验证。
    await tester.scrollUntilVisible(
      find.text('歌词样式'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    expect(find.text('歌词样式'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('沉浸光感'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    expect(find.text('沉浸光感'), findsOneWidget);
    state.dispose();
  });

  testWidgets('音乐厅榜单入口按 chart 类型打开，不再当普通歌单', (tester) async {
    final state = _UiProbeState();
    state.discover = const DiscoverData(
      charts: <Playlist>[
        Playlist(id: '24926', name: '热歌榜', kind: 'chart', songCount: 200),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(900, 800));
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: DiscoverPage(state: state)),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('热歌榜'));
    await tester.pump();
    expect(state.openedPlaylists, hasLength(1));
    expect(state.openedPlaylists.single.id, '24926');
    expect(state.openedPlaylists.single.kind, 'chart');
    state.dispose();
  });

  testWidgets('搜索歌曲 ID 为空时给出 SnackBar，不静默无反应', (tester) async {
    final state = _UiProbeState();
    state.searchResults = <Song>[
      Song(id: '', name: '缺少ID的歌', artists: const <String>['未知']),
    ];
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: SearchPage(state: state)),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('缺少ID的歌'));
    await tester.pump();
    expect(find.textContaining('歌曲 ID 为空'), findsOneWidget);
    expect(state.playedIds, isEmpty);
    state.dispose();
  });
}

class _UiProbeState extends AppState {
  final List<Playlist> openedPlaylists = <Playlist>[];
  final List<String> playedIds = <String>[];

  @override
  Future<void> openPlaylist(Playlist playlist) async {
    openedPlaylists.add(playlist);
    activePlaylist = playlist;
    playlistSongsList = <Song>[];
    refresh();
  }

  @override
  Future<void> play(Song song, {List<Song>? queue}) async {
    playedIds.add(song.id);
    refresh();
  }
}
