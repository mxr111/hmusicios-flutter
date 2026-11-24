import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/services/lyric_progress.dart';

void main() {
  test('逐字进度按字权重连续插值，而不是整字跳变', () {
    final line = LyricLine(
      Duration.zero,
      '你好',
      words: const <LyricWord>[
        LyricWord(Duration.zero, '你'),
        LyricWord(Duration(milliseconds: 1000), '好'),
      ],
    );
    final end = Duration(milliseconds: 2000);

    expect(lyricProgress(line, Duration.zero, lineEnd: end), 0);
    expect(
      lyricProgress(line, const Duration(milliseconds: 250), lineEnd: end),
      closeTo(0.125, 0.0001),
    );
    expect(
      lyricProgress(line, const Duration(milliseconds: 500), lineEnd: end),
      closeTo(0.25, 0.0001),
    );
    expect(
      lyricProgress(line, const Duration(milliseconds: 1200), lineEnd: end),
      closeTo(0.6, 0.0001),
    );
    expect(lyricProgress(line, end, lineEnd: end), 1);
  });

  test('无逐字时间时按整行时长平滑推进', () {
    final line = LyricLine(Duration(milliseconds: 1000), '正在播放');
    expect(
      lyricProgress(line, const Duration(milliseconds: 1500),
          lineEnd: const Duration(milliseconds: 3000)),
      closeTo(0.25, 0.0001),
    );
  });
}
