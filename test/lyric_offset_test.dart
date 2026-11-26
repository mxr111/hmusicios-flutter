import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/services/audio_controller.dart';
import 'package:muyu_flutter/theme.dart';
import 'package:muyu_flutter/widgets/immersive_player.dart';

void main() {
  testWidgets('歌词偏移可按 100ms 正负校准', (tester) async {
    final audio = MuyuAudioController(HuaweiAPI());
    audio.adjustLyricOffset(const Duration(milliseconds: 100));
    expect(audio.lyricOffset, const Duration(milliseconds: 100));

    audio.adjustLyricOffset(const Duration(milliseconds: -200));
    expect(audio.lyricOffset, const Duration(milliseconds: -100));
    audio.dispose();
    await tester.pump();
  });

  testWidgets('歌词偏移限制在正负 5 秒', (tester) async {
    final audio = MuyuAudioController(HuaweiAPI());
    audio.adjustLyricOffset(const Duration(seconds: 6));
    expect(audio.lyricOffset, const Duration(seconds: 5));

    audio.resetLyricOffset();
    audio.adjustLyricOffset(const Duration(seconds: -6));
    expect(audio.lyricOffset, const Duration(seconds: -5));
    audio.dispose();
    await tester.pump();
  });

  testWidgets('歌词位置叠加 ±100ms 校准，不改变单调播放位置', (tester) async {
    final audio = MuyuAudioController(HuaweiAPI());
    await audio.seek(const Duration(seconds: 10));
    expect(audio.lyricPosition, const Duration(seconds: 10));

    audio.adjustLyricOffset(const Duration(milliseconds: 100));
    expect(audio.lyricPosition, const Duration(seconds: 10, milliseconds: 100));

    audio.adjustLyricOffset(const Duration(milliseconds: -300));
    expect(audio.lyricPosition, const Duration(seconds: 9, milliseconds: 800));
    audio.dispose();
    await tester.pump();
  });

  group('歌词聚焦滚动', () {
    List<LyricLine> lines(int count, {String prefix = 'line'}) =>
        List<LyricLine>.generate(
          count,
          (i) => LyricLine(Duration(seconds: i), '$prefix $i'),
          growable: false,
        );

    Widget host(LyricFocusList list) => MaterialApp(
      theme: MuyuTheme.light(),
      home: Scaffold(
        body: Center(child: SizedBox(width: 360, height: 400, child: list)),
      ),
    );

    LyricFocusList list({
      required List<LyricLine> lyrics,
      required ValueNotifier<Duration> position,
      required ScrollController controller,
      required String songId,
    }) => LyricFocusList(
      lines: lyrics,
      position: position,
      pal: kMuyuPalettes.first,
      songId: songId,
      controller: controller,
      onLineTap: (_) {},
    );

    void expectVisible(
      WidgetTester tester,
      int index, {
      String prefix = 'line',
    }) {
      final row = find.text('$prefix $index');
      expect(row, findsOneWidget, reason: '当前行 $index 未被构建/不可见');
      final rowRect = tester.getRect(row);
      final viewRect = tester.getRect(find.byType(ListView));
      expect(
        rowRect.bottom,
        greaterThan(viewRect.top),
        reason: '当前行 $index 滚动到了视口上方',
      );
      expect(
        rowRect.top,
        lessThan(viewRect.bottom),
        reason: '当前行 $index 滚动到了视口下方',
      );
    }

    Future<void> dispose(
      WidgetTester tester,
      ValueNotifier<Duration> position,
      ScrollController controller,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());
      position.dispose();
      controller.dispose();
    }

    testWidgets('播放位置连续推进时当前行始终可见，句内推进不滚动', (tester) async {
      final lyrics = lines(30);
      final position = ValueNotifier<Duration>(Duration.zero);
      final controller = ScrollController();
      await tester.pumpWidget(
        host(
          list(
            lyrics: lyrics,
            position: position,
            controller: controller,
            songId: 'song-a',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expectVisible(tester, 0);

      // 同一句内每 100ms 推进一次：不能触发任何滚动。
      final settled = controller.offset;
      for (var ms = 100; ms < 1000; ms += 100) {
        position.value = Duration(milliseconds: ms);
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          controller.offset,
          moreOrLessEquals(settled, epsilon: 0.01),
          reason: '句内位置推进不应改变滚动 offset',
        );
      }

      // 跨行：每一句切换后当前行都必须留在视口内，且 offset 不超过最大范围。
      for (var i = 1; i < lyrics.length; i++) {
        position.value = Duration(seconds: i, milliseconds: 100);
        await tester.pump();
        await tester.pumpAndSettle();
        expectVisible(tester, i);
        expect(
          controller.offset,
          lessThanOrEqualTo(controller.position.maxScrollExtent + 0.5),
        );
      }

      expect(tester.takeException(), isNull);
      await dispose(tester, position, controller);
    });

    testWidgets('远距离 seek 与回退都会把当前行重新居中', (tester) async {
      final lyrics = lines(60);
      final position = ValueNotifier<Duration>(Duration.zero);
      final controller = ScrollController();
      await tester.pumpWidget(
        host(
          list(
            lyrics: lyrics,
            position: position,
            controller: controller,
            songId: 'song-a',
          ),
        ),
      );
      await tester.pumpAndSettle();

      position.value = const Duration(seconds: 50, milliseconds: 500);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expectVisible(tester, 50);
      final rowRect = tester.getRect(find.text('line 50'));
      final viewRect = tester.getRect(find.byType(ListView));
      expect(
        (rowRect.center.dy - viewRect.center.dy).abs(),
        lessThan(40),
        reason: '中部歌词行应稳定居中',
      );

      position.value = const Duration(seconds: 2, milliseconds: 500);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expectVisible(tester, 2);

      expect(
        controller.offset,
        lessThanOrEqualTo(controller.position.maxScrollExtent + 0.5),
      );
      expect(tester.takeException(), isNull);
      await dispose(tester, position, controller);
    });

    testWidgets('暂停后连续帧不漂移，恢复播放继续跟随换行', (tester) async {
      final lyrics = lines(40);
      final position = ValueNotifier<Duration>(
        const Duration(seconds: 5, milliseconds: 400),
      );
      final controller = ScrollController();
      await tester.pumpWidget(
        host(
          list(
            lyrics: lyrics,
            position: position,
            controller: controller,
            songId: 'song-a',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expectVisible(tester, 5);

      // 暂停：位置停止推进，连续多帧不能产生任何滚动。
      final paused = controller.offset;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        controller.offset,
        moreOrLessEquals(paused, epsilon: 0.01),
        reason: '暂停后歌词不应继续漂移',
      );

      // 恢复：继续推进到下一句，列表重新跟随。
      position.value = const Duration(seconds: 6, milliseconds: 200);
      await tester.pump();
      await tester.pumpAndSettle();
      expectVisible(tester, 6);
      expect(tester.takeException(), isNull);
      await dispose(tester, position, controller);
    });

    testWidgets('切歌与快速连续切歌清空旧滚动，不产生竞态', (tester) async {
      final position = ValueNotifier<Duration>(Duration.zero);
      final controller = ScrollController();
      final first = lines(40, prefix: 'A');

      await tester.pumpWidget(
        host(
          list(
            lyrics: first,
            position: position,
            controller: controller,
            songId: 'song-a',
          ),
        ),
      );
      await tester.pumpAndSettle();
      position.value = const Duration(seconds: 30, milliseconds: 200);
      await tester.pump();
      await tester.pumpAndSettle();
      expectVisible(tester, 30, prefix: 'A');
      final oldOffset = controller.offset;

      // 快速连续切歌：每首只推进一帧，上一首的延迟滚动必须失效。
      final second = lines(40, prefix: 'B');
      position.value = Duration.zero;
      await tester.pumpWidget(
        host(
          list(
            lyrics: second,
            position: position,
            controller: controller,
            songId: 'song-b',
          ),
        ),
      );
      await tester.pump();

      final third = lines(40, prefix: 'C');
      await tester.pumpWidget(
        host(
          list(
            lyrics: third,
            position: position,
            controller: controller,
            songId: 'song-c',
          ),
        ),
      );
      await tester.pump();

      position.value = const Duration(seconds: 3, milliseconds: 200);
      await tester.pump();
      await tester.pumpAndSettle();
      expectVisible(tester, 3, prefix: 'C');
      expect(
        controller.offset,
        lessThan(oldOffset),
        reason: '切到新歌后应回到新歌前部而不是停在旧歌位置',
      );
      expect(tester.takeException(), isNull);
      await dispose(tester, position, controller);
    });
  });
}
