import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/endpoints.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';
import 'package:muyu_flutter/services/app_log.dart';
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

class _VipThenStandardGateway extends HuaweiGateway {
  final List<String> requestedTypes = <String>[];

  @override
  Future<Map<String, dynamic>> request(String path,
      {Map<String, dynamic> body = const <String, dynamic>{}}) async {
    final quality = '${body['qualityType']}';
    requestedTypes.add(quality);
    if (quality == '1') {
      return <String, dynamic>{
        'result': <String, dynamic>{'resultCode': '000000'},
        'qualityType': '1',
        'size': 4332025,
        'fileURL':
            'https://test.dbankcdn.cn/1092974-MP3-128K-FTD.mp3',
      };
    }
    return <String, dynamic>{
      'result': <String, dynamic>{
        'resultCode': '142411',
        'resultMessage': 'Only super diamond vip user can play the content!',
      },
    };
  }
}

class _AllVipGateway extends HuaweiGateway {
  @override
  Future<Map<String, dynamic>> request(String path,
      {Map<String, dynamic> body = const <String, dynamic>{}}) async {
    return <String, dynamic>{
      'result': <String, dynamic>{
        'resultCode': '142411',
        'resultMessage': 'Only super diamond vip user can play the content!',
      },
    };
  }
}

/// 取流接口（任意档位）返回 990000：属于鉴权失败，必须立即中止降档。
class _AuthAtHiResGateway extends HuaweiGateway {
  final List<String> requestedTypes = <String>[];

  @override
  Future<Map<String, dynamic>> request(String path,
      {Map<String, dynamic> body = const <String, dynamic>{}}) async {
    if (path != HuaweiPaths.playUrl) {
      throw StateError('unexpected path $path');
    }
    final quality = '${body['qualityType']}';
    requestedTypes.add(quality);
    if (quality != '1') {
      return <String, dynamic>{
        'result': <String, dynamic>{
          'resultCode': '990000',
          'resultMessage': '鉴权失败',
        },
      };
    }
    return <String, dynamic>{
      'result': <String, dynamic>{'resultCode': '000000'},
      'playQuality': quality,
      'fileURL': 'https://test.dbankcdn.cn/full_MQ.mp3',
    };
  }
}

/// 抛业务异常但调用方不显式传 statusCode，验证构造时自动标记 401。
class _ThrowingAuthGateway extends HuaweiGateway {
  final List<String> requestedTypes = <String>[];

  @override
  Future<Map<String, dynamic>> request(String path,
      {Map<String, dynamic> body = const <String, dynamic>{}}) async {
    requestedTypes.add('${body['qualityType']}');
    throw HuaweiBusinessException('990000', '鉴权失败');
  }
}

void main() {
  test('取流返回 990000：立即抛鉴权错误，不再请求后续档位', () async {
    final gateway = _AuthAtHiResGateway();
    final api = HuaweiAPI(gateway: gateway);

    await expectLater(
      api.audioFiles(
        'auth-song',
        upstreamQualities: const <AudioQuality>{
          AudioQuality.hiRes,
          AudioQuality.lossless,
          AudioQuality.standard,
        },
      ),
      throwsA(
        predicate<Object>((e) {
          final m = e.toString();
          return m.contains('990000') &&
              m.contains('重新登录') &&
              !m.contains('没有可用');
        }),
      ),
    );
    expect(gateway.requestedTypes, <String>['7']);
  });

  test('990000 业务异常自动标记 401，取流在首个档位即中止', () async {
    final gateway = _ThrowingAuthGateway();
    final api = HuaweiAPI(gateway: gateway);

    try {
      await api.audioFiles(
        'auth-song',
        upstreamQualities: const <AudioQuality>{
          AudioQuality.lossless,
          AudioQuality.standard,
        },
      );
      fail('990000 应当抛出鉴权错误');
    } on HuaweiBusinessException catch (e) {
      expect(e.statusCode, 401);
      expect(e.isAuthFailure, isTrue);
    }
    expect(gateway.requestedTypes, <String>['3']);
  });

  test('Hi-Res 142411 不终止链路，继续 standard 兜底并记录 qualityType', () async {
    AppLog.clear();
    final gateway = _VipThenStandardGateway();
    final api = HuaweiAPI(gateway: gateway);
    final files = await api.audioFiles(
      '1092974',
      upstreamQualities: const <AudioQuality>{
        AudioQuality.hiRes,
        AudioQuality.lossless,
        AudioQuality.standard,
      },
    );

    expect(files, isNotEmpty);
    expect(files.first.quality, AudioQuality.standard);
    expect(files.first.qualityType, '1');
    expect(files.first.preview, isFalse);
    expect(files.first.url.toString(), contains('-MP3-128K-FTD.mp3'));
    expect(gateway.requestedTypes, contains('7'));
    expect(gateway.requestedTypes, contains('1'));

    final log = AppLog.exportText();
    expect(log, contains('song=1092974'));
    expect(log, contains('qualityType=7'));
    expect(log, contains('qualityType=1'));
    expect(log, contains('142411'));
    expect(log, contains('choose=standard'));
  });

  test('真 VIP 全档 142411：错误包含 code / 歌曲 ID / 最终档位', () async {
    final api = HuaweiAPI(gateway: _AllVipGateway());

    await expectLater(
      api.audioFiles(
        '110745494',
        upstreamQualities: const <AudioQuality>{
          AudioQuality.hiRes,
          AudioQuality.standard,
        },
      ),
      throwsA(
        predicate<Object>(
          (e) {
            final m = e.toString();
            return m.contains('142411') &&
                m.contains('110745494') &&
                m.contains('standard/') &&
                m.contains('超级钻石 VIP 专享');
          },
        ),
      ),
    );
  });

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
