import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/services/playback_clock.dart';

void main() {
  test('单调时钟逐帧外推，暂停后冻结，恢复不跳变', () {
    var elapsed = Duration.zero;
    final clock = PlaybackClock(elapsed: () => elapsed);
    clock.duration = const Duration(minutes: 4);
    clock.sync(const Duration(seconds: 10), playing: true);

    expect(clock.position, const Duration(seconds: 10));
    elapsed = const Duration(seconds: 1);
    expect(clock.position, const Duration(seconds: 11));

    clock.setPlaying(false);
    elapsed = const Duration(seconds: 5);
    expect(clock.position, const Duration(seconds: 11));

    clock.setPlaying(true);
    expect(clock.position, const Duration(seconds: 11));
    elapsed = const Duration(seconds: 6);
    expect(clock.position, const Duration(seconds: 12));
  });

  test('seek 重新锚定，歌词偏移可正可负并受时长约束', () {
    var elapsed = const Duration(seconds: 3);
    final clock = PlaybackClock(elapsed: () => elapsed);
    clock.duration = const Duration(minutes: 3);
    clock.sync(const Duration(seconds: 20), playing: true);
    clock.seek(const Duration(seconds: 30));

    expect(clock.position, const Duration(seconds: 30));
    expect(
      clock.adjusted(const Duration(milliseconds: -200)),
      const Duration(seconds: 29, milliseconds: 800),
    );
    expect(
      clock.adjusted(const Duration(seconds: 10)),
      const Duration(seconds: 40),
    );

    clock.reset();
    expect(clock.isPlaying, isFalse);
    expect(clock.position, Duration.zero);
    expect(clock.adjusted(const Duration(seconds: -1)), Duration.zero);
  });

  test('重复播放状态不重锚，暂停后的 seek 仍保持暂停', () {
    var elapsed = Duration.zero;
    final clock = PlaybackClock(elapsed: () => elapsed);
    clock.duration = const Duration(minutes: 2);
    clock.sync(const Duration(seconds: 8), playing: true);

    elapsed = const Duration(seconds: 4);
    clock.setPlaying(true); // 重复状态事件不能影响单调时间轴。
    elapsed = const Duration(seconds: 6);
    expect(clock.position, const Duration(seconds: 14));

    clock.setPlaying(false);
    elapsed = const Duration(seconds: 10);
    clock.seek(const Duration(seconds: 40));
    expect(clock.isPlaying, isFalse);
    expect(clock.position, const Duration(seconds: 40));

    clock.setPlaying(false); // 重复暂停也不能导致位置跳变。
    elapsed = const Duration(seconds: 30);
    expect(clock.position, const Duration(seconds: 40));
  });

  test('时长变化同步夹紧当前位置，未知/扩展时长不会倒退', () {
    var elapsed = Duration.zero;
    final clock = PlaybackClock(elapsed: () => elapsed);
    clock.sync(const Duration(seconds: 20), playing: true);
    elapsed = const Duration(seconds: 15);
    expect(clock.position, const Duration(seconds: 35));

    clock.duration = const Duration(seconds: 30);
    expect(clock.position, const Duration(seconds: 30));
    elapsed = const Duration(seconds: 20);
    expect(clock.position, const Duration(seconds: 30));

    clock.duration = const Duration(minutes: 1);
    elapsed = const Duration(seconds: 22);
    expect(clock.position, const Duration(seconds: 32));

    clock.duration = Duration.zero; // duration=0 表示尚未知，不限制位置。
    elapsed = const Duration(seconds: 25);
    expect(clock.position, const Duration(seconds: 35));
  });

  test('时钟源异常倒退时位置不反向，歌词偏移夹在正负五秒', () {
    var elapsed = const Duration(seconds: 5);
    final clock = PlaybackClock(elapsed: () => elapsed);
    clock.sync(const Duration(seconds: 10), playing: true);

    elapsed = const Duration(seconds: 4);
    expect(clock.position, const Duration(seconds: 10));

    expect(
      PlaybackClock.clampOffset(
        const Duration(seconds: 10),
        limit: const Duration(seconds: 5),
      ),
      const Duration(seconds: 5),
    );
    expect(
      PlaybackClock.clampOffset(
        const Duration(seconds: -10),
        limit: const Duration(seconds: 5),
      ),
      const Duration(seconds: -5),
    );
    expect(
      PlaybackClock.clampOffset(
        const Duration(milliseconds: 1200),
        limit: const Duration(seconds: 5),
      ),
      const Duration(milliseconds: 1200),
    );
  });
}
