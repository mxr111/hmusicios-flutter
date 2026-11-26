import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/services/audio_controller.dart';

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
}
