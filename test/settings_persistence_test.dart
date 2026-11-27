import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/models_skin.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/services/audio_controller.dart';
import 'package:muyu_flutter/services/session_store.dart';

class _SettingsAudio extends MuyuAudioController {
  _SettingsAudio() : super(HuaweiAPI());

  @override
  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, 1.0).toDouble();
    notifyListeners();
  }

  @override
  Future<void> setQuality(AudioQuality q) async {
    quality = q;
    notifyListeners();
  }

  @override
  void setEffect(String value) {
    if (MuyuAudioController.kEffects.contains(value)) {
      effect = value;
      notifyListeners();
    }
  }

  @override
  Future<void> adjustLyricOffset(Duration delta) async {
    lyricOffset += delta;
    notifyListeners();
  }

  @override
  Future<void> resetLyricOffset() async {
    lyricOffset = Duration.zero;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const globalAudioChannel = MethodChannel('xyz.luan/audioplayers.global');
  const audioChannel = MethodChannel('xyz.luan/audioplayers');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(globalAudioChannel, (_) async => null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(audioChannel, (_) async => null);

  test('设置 wrapper 立即通知并持久化，restore 后恢复', () async {
    final store = MemorySessionStore();
    final state = AppState(
      sessionStore: store,
      audioController: _SettingsAudio(),
    );
    addTearDown(state.dispose);
    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.lyricsRevision.value;

    state.setTheme(4);
    expect(notifications, greaterThan(0));
    expect(state.lyricsRevision.value, greaterThan(revisionBefore));
    expect(state.playerStyle, PlayerStyle.classic);

    state.setPlayerStyle(PlayerStyle.classic);
    expect(state.playerStyle, PlayerStyle.classic);
    state.updateLyricStyle(
      const LyricStyle(
        align: LyricAlign.center,
        bold: false,
        columns: 2,
        fontScale: 1.2,
        font: '宋体',
        followCoverColor: false,
      ),
    );
    state.setGlass(ImmersiveGlass.thick);
    state.setGlowColor(kGlowColors[2]);
    state.updateSkin(glassPress: false, glassSlide: false);
    await state.setVolume(0.42);
    state.setEffect('低频增厚');
    await state.setQuality(AudioQuality.lossless);
    await state.setLyricOffset(const Duration(milliseconds: 1200));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final snapshot = await store.read();
    expect(snapshot?.themeIndex, 4);
    expect(snapshot?.lyricStyleAlign, LyricAlign.center.index);
    expect(snapshot?.lyricStyleBold, isFalse);
    expect(snapshot?.lyricStyleColumns, 2);
    expect(snapshot?.lyricStyleFontScale, 1.2);
    expect(snapshot?.lyricStyleFont, '宋体');
    expect(snapshot?.lyricStyleFollowCoverColor, isFalse);
    expect(snapshot?.glassIndex, ImmersiveGlass.thick.index);
    expect(snapshot?.glowColorArgb, kGlowColors[2].toARGB32());
    expect(snapshot?.glassPress, isFalse);
    expect(snapshot?.glassSlide, isFalse);
    expect(snapshot?.volume, 0.42);
    expect(snapshot?.effect, '低频增厚');
    expect(snapshot?.qualityName, AudioQuality.lossless.name);
    expect(snapshot?.lyricOffsetMs, 1200);

    final restored = AppState(
      sessionStore: store,
      audioController: _SettingsAudio(),
    );
    addTearDown(restored.dispose);
    var restoreNotifications = 0;
    restored.addListener(() => restoreNotifications++);
    final restoredRevision = restored.lyricsRevision.value;
    await restored.restoreSession();

    expect(restoreNotifications, greaterThan(0));
    expect(
      restored.lyricsRevision.value,
      greaterThan(restoredRevision),
    );
    expect(restored.themeIndex, 4);
    expect(restored.lyricStyle.align, LyricAlign.center);
    expect(restored.lyricStyle.bold, isFalse);
    expect(restored.lyricStyle.columns, 2);
    expect(restored.lyricStyle.fontScale, 1.2);
    expect(restored.lyricStyle.font, '宋体');
    expect(restored.lyricStyle.followCoverColor, isFalse);
    expect(restored.glass, ImmersiveGlass.thick);
    expect(restored.glowColor, kGlowColors[2]);
    expect(restored.glassPress, isFalse);
    expect(restored.glassSlide, isFalse);
    expect(restored.audio.volume, 0.42);
    expect(restored.audio.effect, '低频增厚');
    expect(restored.audio.quality, AudioQuality.lossless);
    expect(restored.audio.lyricOffset, const Duration(milliseconds: 1200));
    expect(restored.playerStyle, PlayerStyle.classic);
  });
}
