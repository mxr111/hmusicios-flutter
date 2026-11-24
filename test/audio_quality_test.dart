import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/endpoints.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';
import 'package:muyu_flutter/services/audio_controller.dart';

class _PlaybackGateway extends HuaweiGateway {
  _PlaybackGateway({this.allAudition = false});

  final bool allAudition;

  @override
  Future<Map<String, dynamic>> request(String path,
      {Map<String, dynamic> body = const <String, dynamic>{}}) async {
    if (path != HuaweiPaths.playUrl) {
      throw StateError('unexpected path $path');
    }
    final quality = '${body['qualityType']}';
    if (allAudition || quality == '7') {
      return <String, dynamic>{
        'result': <String, dynamic>{'resultCode': '000000'},
        'auditionEnd': '60000',
        'auditionTime': '60000',
        'fileURL': 'https://test.dbankcdn.cn/preview_$quality.mp3_AQ.mp3',
      };
    }
    final suffix = switch (quality) {
      '5' => 'HIRES.flac',
      '3' => 'SQ.flac',
      '2' => 'HQ.mp3',
      _ => 'MQ.mp3',
    };
    return <String, dynamic>{
      'result': <String, dynamic>{'resultCode': '000000'},
      'playQuality': quality,
      'fileURL': 'https://test.dbankcdn.cn/full_$suffix',
    };
  }
}

class _FullWithAuditionFieldsGateway extends HuaweiGateway {
  @override
  Future<Map<String, dynamic>> request(String path,
      {Map<String, dynamic> body = const <String, dynamic>{}}) async {
    final quality = '${body['qualityType']}';
    return <String, dynamic>{
      'result': <String, dynamic>{'resultCode': '000000'},
      'auditionEnd': '90000',
      'auditionTime': '30000',
      'playFragmentFlag': '0',
      'fragmentInfo': <String, dynamic>{'hasFragement': '0'},
      'fileURL': 'https://test.dbankcdn.cn/full_$quality.mp3',
    };
  }
}

void main() {
  test('Hi-Res 试听片段会被跳过，回退到完整 Hi-Res 文件', () async {
    final api = HuaweiAPI(gateway: _PlaybackGateway());
    final files = await api.audioFiles(
      'song-1',
      upstreamQualities: const <AudioQuality>{AudioQuality.hiRes},
    );

    // 最高档 + 标准档兜底都会返回；默认播放仍选 Hi-Res。
    expect(files.first.quality, AudioQuality.hiRes);
    expect(files.any((f) => f.quality == AudioQuality.hiRes), isTrue);
    expect(files.first.url.toString(), contains('HIRES.flac'));
    for (final file in files) {
      expect(file.url.toString(), isNot(contains('_AQ')));
    }
  });

  test('标准档请求返回完整文件', () async {
    final api = HuaweiAPI(gateway: _PlaybackGateway());
    final files = await api.audioFiles(
      'song-1',
      upstreamQualities: const <AudioQuality>{AudioQuality.standard},
    );

    expect(files.single.quality, AudioQuality.standard);
    expect(files.single.url.toString(), contains('MQ.mp3'));
  });

  test('全部档位都只有试听时明确报错，不把 30 秒片段当完整歌曲', () async {
    final api = HuaweiAPI(gateway: _PlaybackGateway(allAudition: true));

    expect(
      () => api.audioFiles(
        'song-1',
        upstreamQualities: const <AudioQuality>{AudioQuality.standard},
      ),
      throwsA(isA<HuaweiException>()),
    );
  });

  test('完整歌曲即使带 auditionEnd 字段也不能误判成试听', () async {
    final api = HuaweiAPI(gateway: _FullWithAuditionFieldsGateway());
    final files = await api.audioFiles(
      'song-1',
      upstreamQualities: const <AudioQuality>{AudioQuality.standard},
    );
    expect(files, isNotEmpty);
    expect(files.first.url.toString(), contains('full_1.mp3'));
  });

  test('默认音质选上游最高可播档，用户明确选标准时才降级', () {
    expect(
      MuyuAudioController.chooseQuality(
        AudioQuality.hiRes,
        const <AudioQuality>{
          AudioQuality.standard,
          AudioQuality.lossless,
          AudioQuality.hiRes,
        },
      ),
      AudioQuality.hiRes,
    );
    expect(
      MuyuAudioController.chooseQuality(
        AudioQuality.hiRes,
        const <AudioQuality>{
          AudioQuality.standard,
          AudioQuality.lossless,
        },
      ),
      AudioQuality.lossless,
    );
    expect(
      MuyuAudioController.chooseQuality(
        AudioQuality.standard,
        const <AudioQuality>{
          AudioQuality.standard,
          AudioQuality.hiRes,
        },
      ),
      AudioQuality.standard,
    );
  });
}
