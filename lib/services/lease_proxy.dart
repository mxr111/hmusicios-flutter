import 'dart:io';
import 'dart:math';

import '../protocol/endpoints.dart';
import 'app_log.dart';
/// 与沐语 Go 版 media.Proxy.PublishStream / ServeHTTP / Revoke 对等：
/// 不把华为 CDN 签名 URL 直接交给播放器，而是发布一个本机回环的一次性 URL，
/// 由代理把播放器的 Range 请求透传到远端并回填 Content-Range。
/// 换曲 / 退出登录时 revoke()，旧签名 URL 立刻返回 410 Gone。
class LeaseProxy {
  LeaseProxy._();
  static final LeaseProxy instance = LeaseProxy._();

  HttpServer? _server;
  final Map<String, Uri> _leases = <String, Uri>{};

  int get port => _server?.port ?? 0;
  bool get isActive => _leases.isNotEmpty;

  Future<Uri> publish(Uri remote) async {
    final r = Random.secure();
    final token = List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join();
    _leases[token] = remote;
    // 保留最近 4 条租约，避免快速切歌时上一次 AVPlayer 请求被 410。
    while (_leases.length > 4) {
      _leases.remove(_leases.keys.first);
    }

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
    return Uri.parse('http://127.0.0.1:${_server!.port}/lease/$token');
  }

  void revoke() {
    _leases.clear();
  }

  Future<void> dispose() async {
    revoke();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final token = request.uri.pathSegments.length >= 2
        ? request.uri.pathSegments[1]
        : '';
    final remote = _leases[token];

    if (token.isEmpty || remote == null || !request.uri.path.startsWith('/lease/')) {
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
      // 与沐语一致：CDN 对设备 UA 的签名/防盗链更稳定。
      upstream.headers.set('User-Agent', HuaweiPaths.deviceContext);

      final upstreamResponse = await upstream.close();
      response.statusCode = upstreamResponse.statusCode;
      response.headers.set('Accept-Ranges', 'bytes');
      response.headers.set('Cache-Control', 'no-store');
      var hasContentType = false;
      upstreamResponse.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower == 'content-type') {
          final value = values.join(', ').toLowerCase();
          // 华为 CDN 实测会返回 application/x-zerosize；AVPlayer 可能
          // 因此无法正确探测时长。按扩展名给出标准 MIME。
          final normalized = _normalizeContentType(value);
          if (normalized != null) {
            response.headers.set('Content-Type', normalized);
            hasContentType = true;
          }
          return;
        }
        if (const <String>[
          'content-range',
          'content-length',
          'etag',
          'last-modified',
        ].contains(lower)) {
          response.headers.set(name, values.join(', '));
        }
      });
      if (!hasContentType) {
        final type = _audioContentType(remote);
        if (type != null) response.headers.set('Content-Type', type);
      }
      AppLog.add(
        'proxy',
        '${remote.path} -> ${upstreamResponse.statusCode} '
        'type=${response.headers.contentType} '
        'len=${upstreamResponse.contentLength}',
      );

      if (request.method == 'HEAD') {
        await response.close();
      } else {
        // addStream 逐块转发，不把整首歌读进内存
        await response.addStream(upstreamResponse);
        await response.close();
      }
    } on SocketException {
      AppLog.add('proxy', 'socket error ${remote.path}');
      response.statusCode = HttpStatus.badGateway;
      await response.close();
    } catch (e) {
      AppLog.add('proxy', 'error ${remote.path}: $e');
      try {
        await response.close();
      } catch (_) {
        // 客户端已断开
      }
    } finally {
      client.close();
    }
  }

  static String? _audioContentType(Uri url) {
    final path = url.path.toLowerCase();
    if (path.endsWith('.mp3')) return 'audio/mpeg';
    if (path.endsWith('.flac')) return 'audio/flac';
    if (path.endsWith('.m4a') || path.endsWith('.mp4')) return 'audio/mp4';
    if (path.endsWith('.aac')) return 'audio/aac';
    if (path.endsWith('.wav')) return 'audio/wav';
    if (path.endsWith('.ogg') || path.endsWith('.oga')) return 'audio/ogg';
    return null;
  }

  /// 播放器对非标准写法兼容性不同：日志里华为 FLAC 返回
  /// `audio/x-flac`，iOS AVPlayer 在 setSource 阶段直接失败。
  /// 代理层统一成标准 MIME，减少容器识别失败。
  static String? _normalizeContentType(String raw) {
    final value = raw.split(';').first.trim().toLowerCase();
    if (value.isEmpty ||
        value.contains('zerosize') ||
        value.contains('octet-stream')) {
      return null;
    }
    return switch (value) {
      'audio/x-flac' => 'audio/flac',
      'audio/x-m4a' => 'audio/mp4',
      'audio/x-wav' => 'audio/wav',
      'audio/x-ogg' => 'audio/ogg',
      'audio/mpeg3' || 'audio/x-mpeg-3' => 'audio/mpeg',
      _ => value,
    };
  }
}
