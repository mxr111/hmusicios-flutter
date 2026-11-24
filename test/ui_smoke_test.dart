// UI 冒烟测试：在真实 Flutter widget 树里构建发现页与沉浸播放器，
// 提前抓 analyze 发现不了的运行时构建错误（布局溢出、空数据、null 访问）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models_skin.dart';
import 'package:muyu_flutter/pages/secondary_pages.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/theme.dart';
import 'package:muyu_flutter/widgets/discover_page.dart';
import 'package:muyu_flutter/widgets/immersive_player.dart';
import 'package:muyu_flutter/widgets/netease_home_page.dart';

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

  testWidgets('网易云独立首页在空数据下可构建（推荐歌单/推荐流入口）', (tester) async {
    final state = AppState();
    await tester.pumpWidget(MaterialApp(
      theme: MuyuTheme.light(),
      home: Scaffold(body: NeteaseHomePage(state: state, autoLoad: false)),
    ));
    await tester.pump();

    expect(find.text('主页'), findsOneWidget);
    expect(find.text('网易云音乐'), findsOneWidget);
    expect(find.text('推荐歌单'), findsWidgets); // 金刚入口 + 歌单板块标题
    expect(find.text('推荐流'), findsOneWidget);
    expect(tester.takeException(), isNull);
    state.dispose();
  });

  testWidgets('沉浸播放器在空数据下可构建（无歌词提示 + 播控）', (tester) async {
    final state = AppState();
    await tester.pumpWidget(MaterialApp(
      theme: MuyuTheme.light(),
      home: Scaffold(body: ImmersivePlayer(state: state)),
    ));
    await tester.pump();

    // 默认新版样式 = sonnet 几何艺术字歌词（不再显示封面侧栏的「未在播放」）。
    expect(find.text('正在播放'), findsOneWidget);
    expect(find.textContaining('暂无歌词'), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    state.dispose();
  });

  testWidgets('沐语 4 种播放器样式在空数据下均可构建', (tester) async {
    final state = AppState();
    for (final style in PlayerStyle.values) {
      state.setPlayerStyle(style);
      await tester.pumpWidget(MaterialApp(
        theme: MuyuTheme.light(),
        home: Scaffold(body: ImmersivePlayer(state: state)),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: '${style.label} 构建抛异常');
      expect(find.byIcon(Icons.skip_previous), findsOneWidget,
          reason: '${style.label} 缺少播控');
    }
    state.dispose();
  });

  testWidgets('皮肤外观页可构建且展示 12 款主题', (tester) async {
    final state = AppState();
    await tester.pumpWidget(MaterialApp(
      theme: MuyuTheme.light(),
      home: AppearancePage(state: state),
    ));
    await tester.pump();
    expect(find.text('皮肤与外观'), findsOneWidget);
    // 12 主题色板在 GridView 里（shrinkWrap，全部已构建）。
    for (final p in kMuyuPalettes) {
      expect(find.text(p.label), findsOneWidget, reason: '缺少主题 ${p.label}');
    }
    // 歌词样式与沉浸光感在 ListView 下方，滚动后验证。
    await tester.scrollUntilVisible(find.text('歌词样式'), 300,
        scrollable: find.byType(Scrollable).last);
    await tester.pump();
    expect(find.text('歌词样式'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('沉浸光感'), 300,
        scrollable: find.byType(Scrollable).last);
    await tester.pump();
    expect(find.text('沉浸光感'), findsOneWidget);
    state.dispose();
  });
}
