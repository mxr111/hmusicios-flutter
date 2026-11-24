import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/theme.dart';
import 'package:muyu_flutter/widgets/common.dart';
import 'package:muyu_flutter/widgets/discover_page.dart';
import 'package:muyu_flutter/widgets/home_page.dart';
import 'package:muyu_flutter/widgets/player_bar.dart';

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
    await tester.pumpWidget(MaterialApp(
      theme: MuyuTheme.light(),
      home: Scaffold(body: HomePage(state: state)),
    ));
    await tester.pump();

    expect(find.byType(HomeCard), findsNWidgets(5));
    expect(find.text('为你推荐'), findsOneWidget);
    expect(find.textContaining('晴天'), findsWidgets);
    expect(find.textContaining('每日30首'), findsWidgets);
    expect(find.textContaining('热歌榜'), findsWidgets);

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
    await tester.pumpWidget(MaterialApp(
      theme: MuyuTheme.light(),
      home: Scaffold(body: PlayerBar(state: state)),
    ));

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
    await tester.pumpWidget(MaterialApp(
      theme: MuyuTheme.light(),
      home: Scaffold(body: DiscoverPage(state: state)),
    ));
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
}
