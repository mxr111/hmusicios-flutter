import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/pages/secondary_pages.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/theme.dart';
import 'package:muyu_flutter/widgets/common.dart';
import 'package:muyu_flutter/widgets/home_page.dart';
import 'package:muyu_flutter/widgets/player_bar.dart';

Song _song(String id, String name, {String artist = '测试歌手'}) {
  return Song(
    id: id,
    name: name,
    artists: <String>[artist],
    qualities: const <AudioQuality>{AudioQuality.standard},
  );
}

void main() {
  testWidgets('长歌单默认第一页，切页只改本地状态且点歌传完整队列', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _RecordingState();
    final songs = List<Song>.generate(45, (i) => _song('long-$i', '长歌曲$i'));
    state.activePlaylist = const Playlist(
      id: 'playlist-long',
      name: '长歌单',
      songCount: 45,
      kind: 'collected',
    );
    state.playlistSongsList = songs;

    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: PlaylistDetailPage(state: state),
      ),
    );
    await tester.pump();

    expect(find.text('第 1 / 3 页'), findsOneWidget);
    expect(find.text('长歌曲0'), findsOneWidget);
    expect(find.text('长歌曲20'), findsNothing);

    final refreshBefore = state.refreshHomeCalls;
    await tester.tap(find.text('下一页'));
    await tester.pump();

    expect(find.text('第 2 / 3 页'), findsOneWidget);
    expect(find.text('长歌曲20'), findsOneWidget);
    expect(state.refreshHomeCalls, refreshBefore);

    await tester.tap(find.text('长歌曲20'));
    await tester.pump();

    expect(state.playedIds, <String>['long-20']);
    expect(state.queues.single, hasLength(45));
    expect(state.queues.single.first.id, 'long-0');
    expect(state.queues.single.last.id, 'long-44');
    state.dispose();
  });

  testWidgets('播放队列弹层分页，点队列歌曲仍传完整队列', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _RecordingState();
    final queue = List<Song>.generate(45, (i) => _song('queue-$i', '队列歌曲$i'));
    state.audio.current = queue.first;
    state.audio.queue = queue;

    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: PlayerBar(state: state)),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('播放队列'));
    await tester.pumpAndSettle();

    expect(find.text('播放队列'), findsOneWidget);
    expect(find.text('第 1 / 3 页'), findsOneWidget);
    expect(find.text('队列歌曲20'), findsNothing);

    await tester.tap(find.text('下一页'));
    await tester.pump();
    expect(find.text('第 2 / 3 页'), findsOneWidget);
    expect(find.text('队列歌曲20'), findsOneWidget);

    await tester.tap(find.text('队列歌曲20'));
    await tester.pumpAndSettle();

    expect(state.playedIds, <String>['queue-20']);
    expect(state.queues.single, hasLength(45));
    expect(state.queues.single.first.id, 'queue-0');
    state.dispose();
  });

  testWidgets('歌手简介默认折叠为 3 行，展开后显示全文', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _RecordingState();
    final description = List<String>.generate(
      8,
      (i) => '这是歌手简介的第${i + 1}段，包含作品风格、创作经历与代表专辑介绍。',
    ).join('\n');
    state.activeArtist = Artist(
      id: 'artist-1',
      name: '折叠测试歌手',
      desc: description,
    );
    state.artistSongsList = List<Song>.generate(
      25,
      (i) => _song('artist-song-$i', '歌手歌曲$i'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: ArtistDetailPage(state: state),
      ),
    );
    await tester.pump();

    expect(find.text('展开'), findsOneWidget);
    expect(tester.widget<Text>(find.text(description)).maxLines, 3);

    await tester.tap(find.text('展开'));
    await tester.pump();

    expect(find.text('收起'), findsOneWidget);
    expect(tester.widget<Text>(find.text(description)).maxLines, isNull);
    state.dispose();
  });

  testWidgets('首页空推荐卡打开空态详情页，只有显式重试才刷新', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _RecordingState();
    state.discover = const DiscoverData();

    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: HomePage(state: state)),
      ),
    );
    await tester.pump();

    expect(find.byType(HomeCard), findsAtLeastNWidgets(1));
    // 第一张「现在就听」已改为直接起播；每日30首仍是分页详情。
    await tester.tap(find.byType(HomeCard).at(1));
    await tester.pumpAndSettle();

    expect(find.byType(HomeSectionPage), findsOneWidget);
    expect(find.textContaining('独立板块暂未返回歌曲'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(state.refreshHomeCalls, 0);

    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(state.refreshHomeCalls, 1);
    state.dispose();
  });

  testWidgets('推荐歌单/热歌榜标题可打开分页集合页', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _RecordingState();
    state.discover = DiscoverData(
      playlists: List<Playlist>.generate(
        25,
        (i) => Playlist(id: 'playlist-$i', name: '推荐歌单$i', kind: 'collected'),
      ),
      charts: List<Playlist>.generate(
        21,
        (i) => Playlist(id: 'chart-$i', name: '榜单$i', kind: 'chart'),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: HomePage(state: state)),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('推荐歌单'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeCollectionPage), findsOneWidget);
    expect(find.text('第 1 / 2 页'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('热歌榜'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeCollectionPage), findsOneWidget);
    expect(find.text('第 1 / 2 页'), findsOneWidget);
    state.dispose();
  });

  testWidgets('搜索结果包含歌单 tab，点歌单卡片打开歌单详情', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _RecordingState();
    state.searchPlaylists = List<Playlist>.generate(
      13,
      (i) => Playlist(id: 'search-pl-$i', name: '搜索歌单$i', kind: 'collected'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: SearchPage(state: state)),
      ),
    );
    await tester.pump();

    expect(find.text('歌单 13'), findsOneWidget);
    // 默认歌曲 tab 仍保留；切到歌单 tab 后显示分页网格。
    await tester.tap(find.text('歌单 13'));
    await tester.pump();
    expect(find.byType(PaginatedGrid<Playlist>), findsOneWidget);
    expect(find.text('第 1 / 2 页'), findsOneWidget);
    expect(find.text('搜索歌单0'), findsOneWidget);
    expect(find.text('搜索歌单12'), findsNothing);

    await tester.tap(find.text('搜索歌单0'));
    await tester.pump();
    expect(state.openedPlaylists.single.id, 'search-pl-0');
    state.dispose();
  });

  testWidgets('搜索「加载下一页」仅在 hasMoreSearch 时显示且加载中禁用', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _RecordingState();
    state.searchResults = <Song>[_song('search-1', '搜索结果一')];
    state.hasMoreSearch = true;

    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: SearchPage(state: state)),
      ),
    );
    await tester.pump();

    final loadMore = find.byKey(const ValueKey<String>('search-load-more'));
    expect(loadMore, findsOneWidget);
    expect(find.text('加载下一页'), findsOneWidget);

    state.loadingMoreSearch = true;
    state.refresh();
    await tester.pump();
    final button = tester.widget<FilledButton>(loadMore);
    expect(button.onPressed, isNull);
    expect(find.text('正在加载下一页…'), findsOneWidget);
    expect(
      find.descendant(
        of: loadMore,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    state.loadingMoreSearch = false;
    state.refresh();
    await tester.pump();
    await tester.tap(loadMore);
    await tester.pump();
    await tester.pump();
    expect(state.loadMoreCalls, 1);
    // 失败只提示，不清空已有搜索结果。
    expect(find.text('搜索结果一'), findsOneWidget);
    expect(find.textContaining('加载更多失败测试'), findsWidgets);

    state.hasMoreSearch = false;
    state.refresh();
    await tester.pump();
    expect(loadMore, findsNothing);
    state.dispose();
  });
}

class _RecordingState extends AppState {
  final List<String> playedIds = <String>[];
  final List<List<Song>> queues = <List<Song>>[];
  final List<Playlist> openedPlaylists = <Playlist>[];
  int refreshHomeCalls = 0;
  int loadMoreCalls = 0;

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

  @override
  Future<void> openPlaylist(Playlist playlist) async {
    openedPlaylists.add(playlist);
    activePlaylist = playlist;
    playlistSongsList = <Song>[];
    refresh();
  }

  @override
  Future<void> loadMoreSearch() async {
    loadMoreCalls++;
    error = '加载更多失败测试';
    notifyListeners();
  }
}
