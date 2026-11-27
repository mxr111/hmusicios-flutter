import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/theme.dart';
import 'package:muyu_flutter/widgets/common.dart';
import 'package:muyu_flutter/widgets/discover_page.dart';
import 'package:muyu_flutter/widgets/home_page.dart';
import 'package:muyu_flutter/widgets/sidebar.dart';

const List<String> _otherSourceTexts = <String>[
  '网易云',
  '网易',
  '酷狗',
  'QQ',
  '切换音源',
  '音源切换',
  '4 个音源',
  '多平台',
];

Song _song(String id, {MusicSourceLabel source = MusicSourceLabel.huawei}) {
  return Song(
    id: id,
    name: '华为测试曲 $id',
    artists: const <String>['测试歌手'],
    source: source,
  );
}

void _expectHuaweiOnly(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.byType(Text, skipOffstage: false))
      .map(
        (text) => text.data ?? text.textSpan?.toPlainText() ?? '',
      )
      .join('\n');
  for (final forbidden in _otherSourceTexts) {
    expect(
      texts.contains(forbidden),
      isFalse,
      reason: 'UI 不应出现其他音源文案：$forbidden',
    );
  }
  expect(
    find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString().contains('SourceSwitcher'),
    ),
    findsNothing,
  );
}

void main() {
  testWidgets('首页只显示固定华为音乐标识和华为推荐模块', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1460, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    addTearDown(state.dispose);
    state.discover = DiscoverData(
      recommended: <Song>[
        _song('recommended-1', source: MusicSourceLabel.netease),
      ],
      listen: <Song>[_song('listen-1')],
      playlists: const <Playlist>[
        Playlist(id: 'a001', name: '每日30首', kind: 'collected'),
      ],
      charts: const <Playlist>[
        Playlist(id: '24926', name: '华为热歌榜', kind: 'chart'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: HomePage(state: state)),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('home-source-badge')),
      findsOneWidget,
    );
    expect(find.text('华为音乐'), findsOneWidget);
    expect(find.byType(HomeCard), findsNWidgets(5));
    expect(find.text('为你推荐'), findsOneWidget);
    expect(find.text('推荐歌单'), findsOneWidget);
    expect(find.text('热歌榜'), findsOneWidget);
    _expectHuaweiOnly(tester);
  });

  testWidgets('侧栏固定华为音乐账号文案，自定义入口不出现其他平台', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(
          body: Sidebar(state: state, onSettings: () {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('登录华为音乐'), findsOneWidget);
    expect(find.text('华为音乐账号'), findsOneWidget);
    expect(find.text('本地音乐'), findsOneWidget);
    expect(find.text('设置'), findsNothing);
    _expectHuaweiOnly(tester);
  });

  testWidgets('音乐厅只展示华为榜单与歌单', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    addTearDown(state.dispose);
    state.discover = const DiscoverData(
      playlists: <Playlist>[
        Playlist(id: 'a001', name: '华为每日30首', kind: 'collected'),
      ],
      charts: <Playlist>[
        Playlist(id: '24926', name: '华为热歌榜', kind: 'chart'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: DiscoverPage(state: state)),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('discover-source-badge')),
      findsOneWidget,
    );
    expect(find.text('华为音乐'), findsOneWidget);
    expect(find.text('华为音乐榜单'), findsOneWidget);
    expect(find.text('华为每日30首'), findsOneWidget);
    expect(find.text('华为热歌榜'), findsOneWidget);
    _expectHuaweiOnly(tester);
  });

  testWidgets('SourceBadge 和歌曲行即使收到其他 source 也固定渲染华为', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const SourceBadge(label: '网易云'),
              SongRow(
                song: _song('netease-song', source: MusicSourceLabel.netease),
                onPlay: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('华为音乐'), findsOneWidget);
    expect(find.textContaining('网易'), findsNothing);
    expect(find.textContaining('酷狗'), findsNothing);
    expect(find.textContaining('QQ'), findsNothing);
    expect(find.byIcon(Icons.cloud_queue), findsNothing);
    expect(find.byIcon(Icons.graphic_eq), findsNWidgets(2));
  });
}
