// UI 冒烟测试：在真实 Flutter widget 树里构建发现页与沉浸播放器，
// 提前抓 analyze 发现不了的运行时构建错误（布局溢出、空数据、null 访问）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/theme.dart';
import 'package:muyu_flutter/widgets/discover_page.dart';
import 'package:muyu_flutter/widgets/immersive_player.dart';

void main() {
  testWidgets('发现页在空数据下可构建（推荐歌单/新歌/榜单/电台/收藏）', (tester) async {
    final state = AppState();
    await tester.pumpWidget(MaterialApp(
      theme: MuyuTheme.light(),
      home: Scaffold(body: DiscoverPage(state: state)),
    ));
    await tester.pump();

    expect(find.text('音乐厅'), findsOneWidget);
    expect(find.text('我的收藏'), findsWidgets); // 金刚区 + 收藏板块
    // 下方区块在 ListView 里懒加载，滚动后再验证（字段名来自 REA 反编译）。
    await tester.scrollUntilVisible(find.text('新歌速递'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    expect(find.text('新歌速递'), findsOneWidget);
    state.dispose();
  });

  testWidgets('沉浸播放器在空数据下可构建（无歌词提示 + 播控）', (tester) async {
    final state = AppState();
    await tester.pumpWidget(MaterialApp(
      theme: MuyuTheme.light(),
      home: Scaffold(body: ImmersivePlayer(state: state)),
    ));
    await tester.pump();

    expect(find.text('未在播放'), findsOneWidget);
    expect(find.textContaining('暂无歌词'), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    state.dispose();
  });
}
