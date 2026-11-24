import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/theme.dart';
import 'package:muyu_flutter/widgets/home_page.dart';

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
}
