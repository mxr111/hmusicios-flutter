import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/models_skin.dart';
import 'package:muyu_flutter/pages/secondary_pages.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/services/session_store.dart';

void main() {
  testWidgets('SettingsPage 当前路由内改设置立即刷新', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState(sessionStore: MemorySessionStore());
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(state: state, onLogin: () {}),
      ),
    );

    final beforeDark = state.darkMode;
    await tester.tap(find.byKey(const ValueKey<String>('settings-dark-mode')));
    await tester.pump();
    expect(state.darkMode, isNot(beforeDark));
    expect(
      tester
          .widget<Switch>(
            find.byKey(const ValueKey<String>('settings-dark-mode')),
          )
          .value,
      state.darkMode,
    );

    await tester.tap(find.byKey(const ValueKey<String>('settings-quality')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AudioQuality.standard.label).last);
    await tester.pumpAndSettle();
    expect(state.audio.quality, AudioQuality.standard);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('AppearancePage 当前路由内改主题/歌词样式立即刷新', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState(sessionStore: MemorySessionStore());
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(home: AppearancePage(state: state)),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('appearance-theme-3')),
    );
    await tester.pump();
    expect(state.themeIndex, 3);

    final centerSwitch = find.byKey(
      const ValueKey<String>('appearance-switch-歌词居中'),
    );
    expect(tester.widget<Switch>(centerSwitch).value, isFalse);
    await tester.tap(centerSwitch);
    await tester.pump();
    expect(state.lyricStyle.align, LyricAlign.center);
    expect(tester.widget<Switch>(centerSwitch).value, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
