import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/endpoints.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';

class _AudioGateway extends HuaweiGateway {
  _AudioGateway(this.url);

  final String url;
  final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic> body = const <String, dynamic>{},
  }) async {
    if (path != HuaweiPaths.playUrl) {
      throw StateError('unexpected post $path');
    }
    bodies.add(Map<String, dynamic>.from(body));
    return <String, dynamic>{
      'result': <String, dynamic>{
        'resultCode': HuaweiPaths.successCode,
      },
      'fileURL': url,
      'size': 123456,
    };
  }
}

void main() {
  test('/preview/、_AQ、_PV 试听 URL 都被拒绝', () async {
    for (final url in const <String>[
      'https://music-pics-drcn.dbankcdn.cn/preview/song.mp3',
      'https://music-pics-drcn.dbankcdn.cn/song_AQ.mp3',
      'https://music-pics-drcn.dbankcdn.cn/song_PV.flac',
    ]) {
      final api = HuaweiAPI(gateway: _AudioGateway(url));
      await expectLater(
        api.audioFiles(
          'song-1',
          upstreamQualities: const <AudioQuality>{AudioQuality.standard},
        ),
        throwsA(
          isA<HuaweiException>().having(
            (e) => e.toString(),
            'message',
            contains('只有试听片段'),
          ),
        ),
        reason: url,
      );
    }
  });

  test('完整音频 URL 正常通过并返回标准档', () async {
    const url =
        'https://music-pics-drcn.dbankcdn.cn/audio/song-MP3-128K.mp3';
    final gateway = _AudioGateway(url);
    final api = HuaweiAPI(gateway: gateway);

    final files = await api.audioFiles(
      'song-1',
      upstreamQualities: const <AudioQuality>{AudioQuality.standard},
    );

    expect(files.single.quality, AudioQuality.standard);
    expect(files.single.url.toString(), url);
    expect(files.single.preview, isFalse);
    expect(gateway.bodies, isNotEmpty);
  });
}
