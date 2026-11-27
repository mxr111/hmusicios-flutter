import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../protocol/huawei_oauth.dart';
import '../services/app_state.dart';
import '../theme.dart';

/// 应用内浏览器完成华为账号 OAuth 扫码登录。
///
/// 不跳外部浏览器；授权页在 App 内打开。开启 [autoFillCredentials] 时，
/// 只会把本机保存的账号密码填入华为 OAuth 页面，最终仍需华为授权，
/// hms://redirect_uri 回调由 NavigationDelegate 拦截，
/// 随后用 PKCE verifier 换账号 AT，再换音乐 token + snsUserID。
class OAuthWebViewPage extends StatefulWidget {
  const OAuthWebViewPage({
    super.key,
    required this.state,
    this.autoFillCredentials = false,
  });

  final AppState state;
  final bool autoFillCredentials;

  @override
  State<OAuthWebViewPage> createState() => _OAuthWebViewPageState();
}

/// 统一的 OAuth 路由，便于登录面板和启动自动重登共用同一入口。
MaterialPageRoute<bool> huaweiOAuthRoute(
  AppState state, {
  bool autoFillCredentials = false,
}) {
  return MaterialPageRoute<bool>(
    builder: (_) => OAuthWebViewPage(
      state: state,
      autoFillCredentials: autoFillCredentials,
    ),
    fullscreenDialog: true,
  );
}

class _OAuthWebViewPageState extends State<OAuthWebViewPage> {
  late OAuthAttempt _attempt;
  late final WebViewController _controller;

  bool _settled = false;
  bool _loading = true;
  bool _exchanging = false;
  String? _error;
  int _autoFillAttempts = 0;
  bool _autoFillErrorShown = false;

  @override
  void initState() {
    super.initState();
    _attempt = OAuthAttempt();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(MuyuColors.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (_intercept(url)) return;
            _setLoading(true);
          },
          onPageFinished: (url) {
            if (_intercept(url)) return;
            _setLoading(false);
            unawaited(_autoFillIfNeeded());
          },
          onNavigationRequest: (request) {
            if (_intercept(request.url)) return NavigationDecision.prevent;
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (_settled || !mounted) return;
            setState(() => _error = '页面加载失败：${error.description}');
          },
        ),
      )
      ..loadRequest(_attempt.authorizeUri);
  }

  void _setLoading(bool value) {
    if (!mounted || _loading == value) return;
    setState(() => _loading = value);
  }

  Future<void> _autoFillIfNeeded() async {
    if (!widget.autoFillCredentials ||
        _settled ||
        _exchanging ||
        _autoFillAttempts >= 3) {
      return;
    }
    final credentials = widget.state.savedHuaweiCredentials;
    if (credentials == null) {
      _showAutoFillFailure();
      return;
    }
    _autoFillAttempts++;
    final script = _autoFillScript(credentials.account, credentials.password);
    try {
      final result = await _controller.runJavaScriptReturningResult(script);
      final text = '$result';
      if (!text.contains('"filledPassword":true') &&
          !text.contains('filledPassword: true')) {
        if (_autoFillAttempts >= 3) _showAutoFillFailure();
      }
    } catch (_) {
      _showAutoFillFailure();
    }
  }

  void _showAutoFillFailure() {
    if (!mounted || _autoFillErrorShown) return;
    _autoFillErrorShown = true;
    setState(() {
      _error = '自动填充未完成，请手动完成验证/登录';
    });
  }

  /// 账号密码只用 [jsonEncode] 注入脚本，不写日志，也不拼接到异常文本。
  String _autoFillScript(String account, String password) {
    final accountJson = jsonEncode(account);
    final passwordJson = jsonEncode(password);
    return '''
(function () {
  const account = $accountJson;
  const password = $passwordJson;
  const visible = (el) => {
    const style = window.getComputedStyle(el);
    return style.display !== 'none' && style.visibility !== 'hidden' &&
      el.getClientRects().length > 0 && !el.disabled && !el.readOnly;
  };
  const setValue = (el, value) => {
    const proto = el instanceof HTMLTextAreaElement
      ? HTMLTextAreaElement.prototype
      : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
    setter ? setter.call(el, value) : (el.value = value);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  };
  const inputs = Array.from(document.querySelectorAll('input')).filter(visible);
  const passwordInput = inputs.find((el) => el.type === 'password');
  const accountInput = inputs.find((el) =>
    ['text', 'email', 'tel', 'number', ''].includes(el.type) &&
    !el.value &&
    /(account|user|email|phone|mobile|login|账号|手机|邮箱)/i.test(
      [el.name, el.id, el.placeholder, el.autocomplete].join(' ')
    )
  ) || inputs.find((el) => ['text', 'email', 'tel', 'number'].includes(el.type));
  if (accountInput && account) setValue(accountInput, account);
  if (passwordInput && password) setValue(passwordInput, password);
  const targetInput = passwordInput || accountInput;
  if (targetInput) {
    const scope = targetInput.closest('form') ||
      targetInput.parentElement?.parentElement || document;
    const candidates = Array.from(scope.querySelectorAll(
      'button[type=submit],input[type=submit],button'
    ));
    const button = candidates.find((el) =>
      /(login|log in|sign in|next|continue|登录|下一步|继续)/i.test(
        (el.textContent || el.value || '').trim()
      )
    ) || candidates.find((el) =>
      el.type === 'submit' || el.tagName === 'BUTTON'
    );
    if (button) setTimeout(() => button.click(), 350);
  }
  return JSON.stringify({
    filledAccount: !!accountInput,
    filledPassword: !!passwordInput
  });
})();
''';
  }

  /// 返回 true 表示已拦截（授权回调），调用方必须阻止继续导航。
  bool _intercept(String url) {
    if (!_attempt.isCallback(url)) return false;
    if (!_settled) _exchange(url);
    return true;
  }

  Future<void> _exchange(String url) async {
    if (_settled) return;
    _settled = true;

    final OAuthCallback callback;
    try {
      callback = _attempt.accept(url);
    } catch (e) {
      _fail(e);
      return;
    }

    if (!mounted) return;
    setState(() => _exchanging = true);
    try {
      await widget.state.api.signInWithCode(callback.code, _attempt.verifier);
      if (!mounted) return;
      widget.state.clearReloginRequest();
      widget.state.refresh();
      // 登录成功必须绕过 990000 的 30 秒冷却，真正重新拉首页。
      await widget.state.refreshHome(force: true);
      widget.state.loadLibrary();
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop<bool>(true);
      }
    } catch (e) {
      _fail(e);
    }
  }

  void _fail(Object e) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _exchanging = false;
      _error = e.toString();
    });
  }

  void _retry() {
    _attempt = OAuthAttempt();
    _settled = false;
    setState(() {
      _error = null;
      _exchanging = false;
      _loading = true;
      _autoFillAttempts = 0;
      _autoFillErrorShown = false;
    });
    _controller.loadRequest(_attempt.authorizeUri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MuyuColors.background,
      appBar: AppBar(
        title: const Text('华为账号登录'),
        backgroundColor: MuyuColors.background,
        foregroundColor: MuyuColors.ink,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '取消登录',
          onPressed: () => Navigator.of(context).pop<bool>(false),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新加载',
            onPressed: _retry,
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading || _exchanging)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (_exchanging)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: Text('授权成功，正在换取音乐会话…'),
                  ),
                ),
              ),
            ),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: Card(
                color: MuyuColors.surface,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('登录失败', style: MuyuTheme.section),
                      const SizedBox(height: 6),
                      Text(_error!, style: MuyuTheme.muted),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _retry,
                        child: const Text('重新登录'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
