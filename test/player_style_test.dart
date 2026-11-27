import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models_skin.dart';

void main() {
  test('播放器样式枚举只有 classic，旧持久化值可由 AppState 兼容收敛', () {
    expect(PlayerStyle.values, const <PlayerStyle>[PlayerStyle.classic]);
    expect(PlayerStyle.classic.label, '经典播放器');
    expect(PlayerStyle.classic.desc, '传统封面 + 歌词列表');
    expect(PlayerStyle.classic.icon, Icons.album);
  });
}
