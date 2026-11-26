import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/pages/secondary_pages.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/services/session_store.dart';
import 'package:muyu_flutter/theme.dart';
import 'package:muyu_flutter/widgets/common.dart';
import 'package:muyu_flutter/widgets/discover_page.dart';
import 'package:muyu_flutter/widgets/home_page.dart';
import 'package:muyu_flutter/widgets/player_bar.dart';
import 'package:muyu_flutter/widgets/sidebar.dart';

void main() {
  testWidgets('首页卡片和推荐列表使用真实字段（不再写死歌名）', (tester) async {
    final state = AppState();
    final song = Song(
      id: 's1',
      name: '晴天',
      artists: const <String>['周杰伦'],
      qualities: const <AudioQuality>{AudioQuality.standard},
    );
    state.homeSongs = <Song>[song];
    state.discover = DiscoverData(
      newSongs: <Song>[song],
      radio: <Song>[song],
      playlists: const <Playlist>[
        Playlist(id: 'a001', name: '每日30首', kind: 'collected'),
      ],
      charts: const <Playlist>[
        Playlist(id: '24926', name: '热歌榜', kind: 'chart'),
      ],
    );

    await tester.binding.setSurfaceSize(const Size(1460, 980));
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: HomePage(state: state)),
      ),
    );
    await tester.pump();

    expect(find.byType(HomeCard), findsNWidgets(5));
    expect(find.text('为你推荐'), findsOneWidget);
    expect(find.text('推荐歌单'), findsOneWidget);
    expect(find.textContaining('晴天'), findsWidgets);
    expect(find.textContaining('每日30首'), findsWidgets);
    expect(find.textContaining('热歌榜'), findsWidgets);

    state.dispose();
  });

  testWidgets('iPhone 窄屏主页不溢出，底部仍显示推荐歌单', (tester) async {
    final state = AppState();
    final song = Song(id: 's1', name: '晴天', artists: const <String>['周杰伦']);
    state.homeSongs = <Song>[song];
    state.discover = DiscoverData(
      newSongs: <Song>[song],
      radio: <Song>[song],
      playlists: const <Playlist>[
        Playlist(id: 'a001', name: '每日30首', kind: 'collected'),
        Playlist(id: 'a002', name: '推荐歌单二', kind: 'collected'),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: HomePage(state: state)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('推荐歌单'), findsOneWidget);
    expect(find.text('每日30首'), findsWidgets);
    state.dispose();
  });

  testWidgets('主页为你推荐使用独立私享好歌流，30 首按 5 首一页', (tester) async {
    final state = AppState();
    state.api.gateway.session = MusicSession(
      token: 'test-token',
      snsUserId: 'test-user',
    );
    final recommended = List<Song>.generate(
      30,
      (i) =>
          Song(id: 'rec-$i', name: '私享好歌$i', artists: const <String>['真实歌手']),
    );
    state.homeSongs = recommended;
    state.discover = DiscoverData(
      recommended: recommended,
      listen: recommended.take(3).toList(),
      newSongs: <Song>[
        Song(id: 'new-only', name: '新歌推荐字段', artists: <String>['新歌手']),
      ],
    );

    await tester.binding.setSurfaceSize(const Size(1460, 980));
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: HomePage(state: state)),
      ),
    );
    await tester.pump();

    expect(find.text('1/6'), findsOneWidget);
    expect(find.text('私享好歌0', skipOffstage: false), findsOneWidget);
    expect(find.text('私享好歌5', skipOffstage: false), findsNothing);
    state.dispose();
  });

  testWidgets('首页五张卡使用各自栏目数据，不再复用同一首歌', (tester) async {
    final state = AppState();
    Song song(String name) =>
        Song(id: name, name: name, artists: const <String>['真实歌手']);
    final recommended = List<Song>.generate(5, (i) => song('为你推荐$i'));
    state.homeSongs = recommended;
    state.discover = DiscoverData(
      recommended: recommended,
      listen: <Song>[song('现在就听曲')],
      daily: <Song>[song('每日30首曲')],
      heart: <Song>[song('心动模式曲')],
      newSongs: <Song>[song('新歌推荐曲')],
      hot: <Song>[song('热歌速递曲')],
    );

    await tester.binding.setSurfaceSize(const Size(1460, 980));
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: HomePage(state: state)),
      ),
    );
    await tester.pump();

    expect(find.byType(HomeCard), findsNWidgets(5));
    for (final name in const <String>[
      '现在就听曲',
      '每日30首曲',
      '心动模式曲',
      '新歌推荐曲',
      '热歌速递曲',
    ]) {
      expect(find.textContaining(name), findsOneWidget);
    }
    state.dispose();
  });

  testWidgets('五卡 subtitles 各不相同，为你推荐 1/5、热歌榜 1/10', (tester) async {
    final state = AppState();
    Song song(String name) =>
        Song(id: name, name: name, artists: const <String>['真实歌手']);
    state.discover = DiscoverData(
      recommended: List<Song>.generate(25, (i) => song('为你推荐$i')),
      listen: <Song>[song('现在就听曲')],
      daily: <Song>[song('每日30首曲')],
      heart: <Song>[song('心动模式曲')],
      newSongs: <Song>[song('新歌推荐曲')],
      hot: <Song>[song('热歌速递曲')],
      playlists: const <Playlist>[
        Playlist(id: 'pl-1', name: '推荐歌单一', kind: 'collected'),
      ],
      charts: List<Playlist>.generate(
        10,
        (i) => Playlist(id: 'chart-$i', name: '榜单$i', kind: 'chart'),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1460, 980));
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: HomePage(state: state)),
      ),
    );
    await tester.pump();

    final subtitles = <String>{
      '现在就听曲 · 真实歌手',
      '每日30首曲 · 真实歌手',
      '心动模式曲 · 真实歌手',
      '新歌推荐曲 · 真实歌手',
      '热歌速递曲 · 真实歌手',
    };
    for (final text in subtitles) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('1/5'), findsOneWidget);
    expect(find.text('1/10'), findsOneWidget);
    expect(find.text('上一组'), findsOneWidget);
    expect(find.text('下一组'), findsOneWidget);
    state.dispose();
  });

  testWidgets('点播放条进入全屏播放器，点歌词按钮进入歌词视图', (tester) async {
    final state = AppState();
    state.audio.current = Song(
      id: 's1',
      name: '晴天',
      artists: const <String>['周杰伦'],
      durationMs: 269000,
    );
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: PlayerBar(state: state)),
      ),
    );

    await tester.tap(find.byType(VinylCover).first);
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.showPlayer, isTrue);
    expect(state.showLyrics, isFalse);

    await tester.tap(find.byIcon(Icons.lyrics_outlined));
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.showLyrics, isTrue);

    state.closeFullPlayer();
    expect(state.showPlayer, isFalse);
    expect(state.showLyrics, isFalse);
    state.dispose();
  });

  testWidgets('音乐厅展示华为榜单，点榜单进入榜单歌单', (tester) async {
    final state = AppState();
    state.discover = const DiscoverData(
      charts: <Playlist>[
        Playlist(id: '24926', name: '热歌榜', kind: 'chart', songCount: 200),
        Playlist(id: '24931', name: '新歌榜', kind: 'chart', songCount: 100),
      ],
      playlists: <Playlist>[
        Playlist(id: 'a001', name: '每日30首', kind: 'collected'),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: DiscoverPage(state: state)),
      ),
    );
    await tester.pump();

    expect(find.text('华为音乐榜单'), findsOneWidget);
    expect(find.text('热歌榜'), findsOneWidget);
    expect(find.text('新歌榜'), findsOneWidget);

    await tester.tap(find.text('热歌榜'));
    await tester.pump();
    expect(state.activePlaylist?.id, '24926');
    expect(state.activePlaylist?.kind, 'chart');

    state.dispose();
  });

  testWidgets('设置页可打开且不会因布局卡死', (tester) async {
    final state = AppState();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: SettingsPage(state: state, onLogin: () {}),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('默认音质'), findsOneWidget);
    expect(find.text('皮肤与外观'), findsOneWidget);
    state.dispose();
  });

  testWidgets('深色开关在浅色/深色主题之间切换，不循环 12 套主题', (tester) async {
    final state = AppState(sessionStore: MemorySessionStore());
    expect(state.darkMode, isFalse);

    state.toggleDarkMode();
    expect(state.darkMode, isTrue);

    state.toggleDarkMode();
    expect(state.darkMode, isFalse);
    state.dispose();
  });

  testWidgets('左上角账号未登录时显示真实登录入口并可点击', (tester) async {
    final state = AppState(sessionStore: MemorySessionStore());
    var tapped = 0;
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(
          body: Sidebar(
            state: state,
            onSettings: () {},
            onAccount: () => tapped++,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('登录华为音乐'), findsOneWidget);
    expect(find.text('土豆'), findsNothing);
    await tester.tap(find.text('登录华为音乐'));
    expect(tapped, 1);
    state.dispose();
  });

  testWidgets('首页 5 张卡 + 为你推荐使用各自独立队列，换组不触发请求', (tester) async {
    final state = _RecordingState();
    state.api.gateway.session = MusicSession(
      token: 'ui-test-token',
      snsUserId: 'ui-test-user',
    );
    Song song(String id) =>
        Song(id: id, name: '曲-$id', artists: const <String>['真实歌手']);
    final recommended = <Song>[song('rec-1'), song('rec-2')];
    final listen = <Song>[song('listen-1')];
    final daily = <Song>[song('daily-1')];
    final heart = <Song>[song('heart-1')];
    final newSongs = <Song>[song('new-1')];
    final hot = <Song>[song('hot-1')];
    state.discover = DiscoverData(
      recommended: recommended,
      listen: listen,
      daily: daily,
      heart: heart,
      newSongs: newSongs,
      hot: hot,
    );

    await tester.binding.setSurfaceSize(const Size(1460, 1400));
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: HomePage(state: state)),
      ),
    );
    await tester.pump();

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byType(HomeCard).at(i));
      await tester.pump();
    }
    expect(state.playedIds, <String>[
      'listen-1',
      'daily-1',
      'heart-1',
      'new-1',
      'hot-1',
    ]);
    expect(state.queues[0].map((s) => s.id), <String>['listen-1']);
    expect(state.queues[1].map((s) => s.id), <String>['daily-1']);
    expect(state.queues[2].map((s) => s.id), <String>['heart-1']);
    expect(state.queues[3].map((s) => s.id), <String>['new-1']);
    expect(state.queues[4].map((s) => s.id), <String>['hot-1']);

    state.playedIds.clear();
    state.queues.clear();
    await tester.tap(find.text('曲-rec-1'));
    await tester.pump();
    expect(state.playedIds, <String>['rec-1']);
    expect(state.queues.single.map((s) => s.id), <String>['rec-1', 'rec-2']);

    final before = state.refreshHomeCalls;
    await tester.tap(find.text('下一组'));
    await tester.pump();
    expect(state.refreshHomeCalls, before);
    state.dispose();
  });

  testWidgets('搜索结果行调用 state.play，并传入完整当前结果队列', (tester) async {
    final state = _RecordingState();
    state.searchResults = <Song>[
      Song(id: 'search-1', name: '搜索结果一', artists: const <String>['A']),
      Song(id: 'search-2', name: '搜索结果二', artists: const <String>['B']),
    ];
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: SearchPage(state: state)),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('搜索结果一'));
    await tester.pump();
    expect(state.playedIds, <String>['search-1']);
    expect(
      state.queues.single.map((s) => s.id),
      <String>['search-1', 'search-2'],
    );
    state.dispose();
  });

  testWidgets('榜单详情歌曲行可播放，播放全部使用榜单歌曲队列', (tester) async {
    final state = _RecordingState();
    state.activePlaylist = const Playlist(
      id: '24926',
      name: '热歌榜',
      kind: 'chart',
    );
    state.playlistSongsList = <Song>[
      Song(id: 'chart-1', name: '榜单歌1', artists: const <String>['A']),
      Song(id: 'chart-2', name: '榜单歌2', artists: const <String>['B']),
    ];
    await tester.binding.setSurfaceSize(const Size(900, 800));
    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: PlaylistDetailPage(state: state),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('榜单歌1'));
    await tester.pump();
    expect(state.playedIds, <String>['chart-1']);
    expect(state.queues.single.map((s) => s.id), <String>['chart-1', 'chart-2']);

    state.playedIds.clear();
    state.queues.clear();
    await tester.tap(find.text('播放全部'));
    await tester.pump();
    expect(state.playedIds, <String>['chart-1']);
    expect(state.queues.single.map((s) => s.id), <String>['chart-1', 'chart-2']);
    state.dispose();
  });
}

class _RecordingState extends AppState {
  final List<String> playedIds = <String>[];
  final List<List<Song>> queues = <List<Song>>[];
  int refreshHomeCalls = 0;

  @override
  Future<void> play(Song song, {List<Song>? queue}) async {
    playedIds.add(song.id);
    queues.add(List<Song>.of(queue ?? <Song>[song]));
    refresh();
  }

  @override
  Future<void> refreshHome({bool force = true}) async {
    refreshHomeCalls++;
    refresh();
  }
}
