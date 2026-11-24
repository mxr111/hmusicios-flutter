// Opt-in: MUYU_HUAWEI_TOKEN=security:... flutter test test/live_audio_probe_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/protocol/endpoints.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';

void main() {
  final token = Platform.environment['MUYU_HUAWEI_TOKEN'] ?? '';
  test('inspect huawei playback fragments', () async {
    final gateway = HuaweiGateway();
    gateway.session = MusicSession(token: token, snsUserId: 'probe');
    final api = HuaweiAPI(gateway: gateway);
    final songs = await api.favorites(fetchAll: false, limit: 1);
    final song = songs.first;
    for (final q in const <String>['1', '2', '3', '5', '7']) {
      try {
        final json = await gateway.request(HuaweiPaths.playUrl, body: {
          'contentCode': song.id,
          'contentType': '1',
          'qualityType': q,
        });
        // ignore: avoid_print
        print('Q$q keys=${json.keys.toList()}');
        // ignore: avoid_print
        print('Q$q fileURL=${json['fileURL']}');
        // ignore: avoid_print
        print('Q$q size=${json['fileSize']} dur=${json['duration']} '
            'fragment=${json['fragmentInfo']} flag=${json['playFragmentFlag']} '
            'preview=${json['previewURL']}');
        final url = json['fileURL'];
        if (url is String && url.isNotEmpty) {
          final client = HttpClient();
          final req = await client.getUrl(Uri.parse(url));
          final resp = await req.close();
          // ignore: avoid_print
          print('Q$q HTTP ${resp.statusCode} length=${resp.contentLength} '
              'type=${resp.headers.contentType}');
          client.close(force: true);
        }
      } catch (e) {
        // ignore: avoid_print
        print('Q$q ERR $e');
      }
    }
  }, skip: token.isEmpty, timeout: const Timeout(Duration(minutes: 3)));
}
