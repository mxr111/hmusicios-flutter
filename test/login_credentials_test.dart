import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/pages/secondary_pages.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/services/session_store.dart';
import 'package:muyu_flutter/widgets/oauth_webview_page.dart';

void main() {
  testWidgets('LoginSheet 保存调 AppState wrapper，且不打印密码', (tester) async {
    final originalDebugPrint = debugPrint;
    final output = <String>[];
    final state = AppState(sessionStore: MemorySessionStore());
    addTearDown(state.dispose);
    bool? autoFill;
    var routed = false;

    Route<bool> fakeRoute(
      AppState appState, {
      bool autoFillCredentials = false,
    }) {
      autoFill = autoFillCredentials;
      routed = true;
      return MaterialPageRoute<bool>(
        builder: (_) => const Scaffold(body: Text('oauth-fake')),
      );
    }

    try {
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LoginSheet(
                state: state,
                oauthRouteBuilder: fakeRoute,
              ),
            ),
          ),
        ),
      );

      final passwordField = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('login-password')),
      );
      expect(passwordField.obscureText, isTrue);

      const account = 'demo-account';
      const password = 'demo-password-value';
      await tester.enterText(
        find.byKey(const ValueKey<String>('login-account')),
        account,
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('login-password')),
        password,
      );
      await tester.tap(find.byKey(const ValueKey<String>('login-save-oauth')));
      await tester.pumpAndSettle();

      expect(routed, isTrue);
      expect(autoFill, isTrue);
      expect(
        state.savedHuaweiCredentials,
        const HuaweiCredentials(account: account, password: password),
      );
      expect(output.join('\n'), isNot(contains(password)));
    } finally {
      debugPrint = originalDebugPrint;
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('OAuth 路由保留 autoFillCredentials 参数', (tester) async {
    final state = AppState(sessionStore: MemorySessionStore());
    addTearDown(state.dispose);
    OAuthWebViewPage? page;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            page = huaweiOAuthRoute(
              state,
              autoFillCredentials: true,
            ).builder(context) as OAuthWebViewPage;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(page?.autoFillCredentials, isTrue);
  });
}
