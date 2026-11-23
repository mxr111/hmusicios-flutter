import 'dart:io';
import 'dart:math';

/// 与沐语 Go 版 media.Proxy.PublishStream / ServeHTTP / Revoke 对等：
/// 不把华为 CDN 签名 URL 直接交给播放器，而是发布一个本机回环的一次性 URL，
/// 由代理把播放器的 Range 请求透传到远端并回填 Content-Range。
/// 换曲 / 退出登录时 revoke()，旧签名 URL 立刻返回 410 Gone。
class LeaseProxy {
  LeaseProxy._();
  static final LeaseProxy instance = LeaseProxy._();

  HttpServer? _server;
  String? _token;
  Uri? _remote;

  int get port => _server?.port ?? 0;
  bool get isActive => _token != null && _remote != null;

  Future<Uri> publish(Uri remote) async {
    revoke();
    final r = Random.secure();
    _token = List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join();
    _remote = remote;

    if (_server == null) {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // 一个 HttpServer 只能 listen 一次；后续 publish 仅替换 token / remote。
      _server!.listen(
        _handle,
        onError: (Object error, StackTrace stack) {
          // 单个连接的错误不影响监听器继续服务
        },
      );
    }
    return Uri.parse('http://127.0.0.1:${_server!.port}/lease/$_token');
  }

  void revoke() {
    _token = null;
    _remote = null;
  }

  Future<void> dispose() async {
    revoke();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final token = _token;
    final remote = _remote;

    if (token == null ||
        remote == null ||
        request.uri.path != '/lease/$token') {
      response.statusCode = HttpStatus.gone;
      await response.close();
      return;
    }

    final client = HttpClient();
    try {
      final upstream = await client.getUrl(remote);
      // AVPlayer / ExoPlayer 会先发 bytes=0-1 探测 Range，必须原样透传
      request.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (const <String>[
          'range',
          'if-none-match',
          'if-range',
          'if-modified-since',
          'accept',
        ].contains(lower)) {
          upstream.headers.set(name, values.join(', '));
        }
      });
      upstream.headers.set('User-Agent', 'MuyuFlutter/1.0');

      final upstreamResponse = await upstream.close();
      response.statusCode = upstreamResponse.statusCode;
      response.headers.set('Accept-Ranges', 'bytes');
      response.headers.set('Cache-Control', 'no-store');
      upstreamResponse.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (const <String>[
          'content-type',
          'content-range',
          'content-length',
          'etag',
          'last-modified',
        ].contains(lower)) {
          response.headers.set(name, values.join(', '));
        }
      });

      if (request.method == 'HEAD') {
        await response.close();
      } else {
        // addStream 逐块转发，不把整首歌读进内存
        await response.addStream(upstreamResponse);
        await response.close();
      }
    } on SocketException {
      response.statusCode = HttpStatus.badGateway;
      await response.close();
    } catch (_) {
      try {
        await response.close();
      } catch (_) {
        // 客户端已断开
      }
    } finally {
      client.close();
    }
  }
}
