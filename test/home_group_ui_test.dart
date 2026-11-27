import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/theme.dart';
import 'package:muyu_flutter/widgets/common.dart';
import 'package:muyu_flutter/widgets/home_page.dart';

Song _song(String id) =>
    Song(id: id, name: id, artists: const <String>['真实歌手']);

void main() {
  testWidgets('首页「上一页/下一页」按各板块真实列表长度分页，只改本地预览', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1460, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _RecordingState();
    state.discover = DiscoverData(
      listen: List<Song>.generate(6, (i) => _song('listen-$i')),
      daily: List<Song>.generate(11, (i) => _song('daily-$i')),
      heart: <Song>[_song('heart-0')],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: HomePage(state: state)),
      ),
    );
    await tester.pump();

    // 最长板块 11 首 -> 每页 5 首 -> 3 页，不是固定 5 页。
    expect(find.text('第 1 / 3 页'), findsOneWidget);
    expect(find.text('listen-0 · 真实歌手'), findsOneWidget);
    expect(find.text('daily-0 · 真实歌手'), findsOneWidget);
    expect(find.text('heart-0 · 真实歌手'), findsOneWidget);

    final refreshBefore = state.refreshHomeCalls;
    await tester.tap(find.text('下一页'));
    await tester.pump();

    expect(find.text('第 2 / 3 页'), findsOneWidget);
    expect(find.text('listen-5 · 真实歌手'), findsOneWidget);
    expect(find.text('daily-5 · 真实歌手'), findsOneWidget);
    // 只有 1 首的板块按自己的长度回绕，不做 fake 填充。
    expect(find.text('heart-0 · 真实歌手'), findsOneWidget);
    expect(state.refreshHomeCalls, refreshBefore);
    expect(state.cardActions, isEmpty);

    await tester.tap(find.text('下一页'));
    await tester.pump();
    expect(find.text('第 3 / 3 页'), findsOneWidget);
    expect(find.text('daily-10 · 真实歌手'), findsOneWidget);
    expect(find.text('listen-4 · 真实歌手'), findsOneWidget);
    expect(state.refreshHomeCalls, refreshBefore);

    await tester.tap(find.text('上一页'));
    await tester.pump();
    expect(find.text('第 2 / 3 页'), findsOneWidget);
    state.dispose();
  });

  testWidgets('首页板块全空时显示空态与显式重试，不自动刷新', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1460, 1100));
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

    const message = '首页推荐板块暂未返回数据。只有点击「重试」才会重新加载。';
    final panel = find.widgetWithText(StatePanel, message);
    expect(panel, findsOneWidget);
    expect(state.refreshHomeCalls, 0);

    await tester.tap(find.descendant(of: panel, matching: find.text('重试')));
    await tester.pump();
    expect(state.refreshHomeCalls, 1);
    state.dispose();
  });
}

class _RecordingState extends AppState {
  final List<String> cardActions = <String>[];
  int refreshHomeCalls = 0;

  @override
  Future<void> playCard(String action) async {
    cardActions.add(action);
    refresh();
  }

  @override
  Future<void> refreshHome({bool force = true}) async {
    refreshHomeCalls++;
    refresh();
  }
}
