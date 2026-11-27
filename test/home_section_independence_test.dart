import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/endpoints.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';

class _SectionGateway extends HuaweiGateway {
  _SectionGateway({this.allSameSong = false});

  final bool allSameSong;
  final List<String> posts = <String>[];

  Map<String, dynamic> _song(String id, String name) => <String, dynamic>{
    'contentID': id,
    'contentName': name,
  };

  @override
  Future<Map<String, dynamic>> get(String path) async {
    if (path.startsWith(
      '/music-operation-service/v1/service/page/detail/all',
    )) {
      final id = allSameSong ? 'same-1' : null;
      return <String, dynamic>{
        'result': <String, dynamic>{
          'columnInfoExs': <dynamic>[
            <String, dynamic>{
              'columnInfo': <String, dynamic>{'columnID': 'home'},
              'contentSimpleInfos': <dynamic>[
                <String, dynamic>{
                  'contentID': 'pmf001',
                  'contentType': '12',
                  'contentName': '现在就听',
                  'listRcmInfos': <dynamic>[
                    if (allSameSong) _song('same-1', '同一首'),
                  ],
                  'childSimpleInfos': <dynamic>[
                    <String, dynamic>{
                      'contentID': 'heart-batch',
                      'contentName': 'heart 心动',
                      'listRcmInfos': <dynamic>[
                        id == null ? _song('heart-1', '心动一') : _song(id, '同一首'),
                      ],
                    },
                    <String, dynamic>{
                      'contentID': 'new-batch',
                      'contentName': 'new 新歌',
                      'listRcmInfos': <dynamic>[
                        id == null ? _song('new-1', '新歌一') : _song(id, '同一首'),
                      ],
                    },
                    <String, dynamic>{
                      'contentID': 'hot-batch',
                      'contentName': 'hot 热歌',
                      'listRcmInfos': <dynamic>[
                        id == null ? _song('hot-1', '热歌一') : _song(id, '同一首'),
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        },
      };
    }
    if (path.startsWith(HuaweiAPI.featuredColumnPath)) {
      return <String, dynamic>{
        'result': <String, dynamic>{
          'listRcmInfos': <dynamic>[if (allSameSong) _song('same-1', '同一首')],
        },
      };
    }
    if (path.startsWith(HuaweiAPI.dailyPlaylistPath)) {
      return <String, dynamic>{
        'result': <String, dynamic>{
          'songSimpleInfos': <dynamic>[
            allSameSong ? _song('same-1', '同一首') : _song('daily-1', '每日一'),
          ],
        },
      };
    }
    if (path.contains('/chart/detail/bychartid')) {
      return <String, dynamic>{
        'result': <String, dynamic>{
          'songSimpleInfos': <dynamic>[
            allSameSong ? _song('same-1', '同一首') : _song('chart-1', '热歌榜一'),
          ],
        },
      };
    }
    throw StateError('unexpected get $path');
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic> body = const <String, dynamic>{},
  }) async {
    posts.add(path);
    if (path.endsWith('/recommend/privatefm')) {
      if (!allSameSong) throw const HuaweiException('HTTP 400');
      return <String, dynamic>{
        'result': <String, dynamic>{
          'listRcmInfos': <dynamic>[_song('same-1', '同一首')],
        },
      };
    }
    if (path.endsWith('/recommend/playlist')) {
      throw const HuaweiException('HTTP 400');
    }
    if (path == HuaweiPaths.playlistDetail) {
      return <String, dynamic>{
        'result': <String, dynamic>{
          'favoriteInfos': <dynamic>[
            <String, dynamic>{
              'contentID': 'library-1',
              'contentName': '账号真实歌单',
              'contentType': 4,
            },
          ],
        },
      };
    }
    throw StateError('unexpected post $path');
  }
}

void main() {
  test('8011 空 / recommend 400 / pmf001 顶层无直接歌曲时 listen 保持空态', () async {
    final gateway = _SectionGateway();
    final api = HuaweiAPI(gateway: gateway);
    final d = await api.discover();

    expect(d.recommended, isEmpty, reason: '8011 没有歌时不能拿别的板块填');
    expect(d.listen, isEmpty, reason: 'pmf001 顶层没有直接歌曲，子批次不能冒充');
    expect(d.heart.single.id, 'heart-1');
    expect(d.newSongs.single.id, 'new-1');
    expect(d.daily.single.id, 'daily-1');
    expect(d.hot.single.id, 'chart-1');
    expect(d.radio, isNotEmpty, reason: 'radio 是聚合页自己的真实数据');

    expect(d.playlists.any((p) => p.id == 'a001'), isTrue);
    expect(
      d.playlists.any((p) => p.id == 'library-1'),
      isTrue,
      reason: 'recommend/playlist 400 只回退真实账号歌单',
    );
    expect(d.playlists.any((p) => p.id == 'recommend-playlist'), isFalse);
    expect(
      gateway.posts.any((p) => p.contains('/recommend/privatefm')),
      isFalse,
      reason: 'discover 不再请求 privatefm，失败也不会影响 listen',
    );
  });

  test('同一首歌跨板块出现时，各板块内部去重后仍各自保留', () async {
    final gateway = _SectionGateway(allSameSong: true);
    final api = HuaweiAPI(gateway: gateway);
    final d = await api.discover();

    for (final songs in <List<Song>>[
      d.listen,
      d.daily,
      d.heart,
      d.newSongs,
      d.hot,
      d.recommended,
    ]) {
      expect(songs.single.id, 'same-1');
    }
    expect(
      gateway.posts.any((p) => p.contains('/recommend/privatefm')),
      isFalse,
      reason: 'discover 不再请求 privatefm',
    );
  });
}
