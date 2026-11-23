import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../protocol/huawei_oauth.dart';
import '../services/app_state.dart';
import '../theme.dart';

/// 应用内浏览器完成华为账号 OAuth 扫码登录。
///
/// 不跳外部浏览器、不用账号密码：授权页在 App 内打开，
/// hms://redirect_uri 回调由 NavigationDelegate 拦截，
/// 随后用 PKCE verifier 换账号 AT，再换音乐 token + snsUserID。
class OAuthWebViewPage extends StatefulWidget {
  const OAuthWebViewPage({super.key, required this.state});

  final AppState state;

  @override
  State<OAuthWebViewPage> createState() => _OAuthWebViewPageState();
}

class _OAuthWebViewPageState extends State<OAuthWebViewPage> {
  late OAuthAttempt _attempt;
  late final WebViewController _controller;

  bool _settled = false;
  bool _loading = true;
  bool _exchanging = false;
  String? _error;

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
      widget.state.refresh();
      widget.state.loadHome();
      widget.state.loadLibrary();
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
