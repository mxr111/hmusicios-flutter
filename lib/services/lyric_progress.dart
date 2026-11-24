import '../models.dart';

/// 逐字歌词的连续演唱进度（0~1）。
///
/// 关键：按「字数权重」在相邻字时间点之间插值，而不是把进度取整到字符。
/// 这样 120Hz 屏幕每帧都能得到亚字符级位置，实现平滑扫光而非逐字跳色。
double lyricProgress(
  LyricLine line,
  Duration position, {
  Duration? lineEnd,
}) {
  if (line.words.isEmpty) {
    final end = lineEnd;
    if (end == null || end <= line.time) return 0;
    return _ratio(position - line.time, end - line.time);
  }

  var totalUnits = 0;
  for (final word in line.words) {
    totalUnits += word.text.length;
  }
  if (totalUnits == 0) return 0;

  var sungUnits = 0.0;
  for (var i = 0; i < line.words.length; i++) {
    final word = line.words[i];
    final start = word.time;
    if (position <= start) break;
    final end = i + 1 < line.words.length
        ? line.words[i + 1].time
        : (lineEnd != null && lineEnd > start
            ? lineEnd
            : start + const Duration(milliseconds: 800));
    sungUnits += word.text.length * _ratio(position - start, end - start);
  }
  return (sungUnits / totalUnits).clamp(0.0, 1.0);
}

double _ratio(Duration elapsed, Duration span) {
  if (span.inMicroseconds <= 0) return 1;
  return (elapsed.inMicroseconds / span.inMicroseconds).clamp(0.0, 1.0);
}
