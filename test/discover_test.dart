import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';

class _FakeGateway extends HuaweiGateway {
  _FakeGateway({this.fail990000Times = 0});

  final List<String> gets = <String>[];
  final List<String> posts = <String>[];
  int fail990000Times;
  int musicTokenExchanges = 0;

  Map<String, dynamic> home = <String, dynamic>{
    'result': <String, dynamic>{'columnInfoExs': <dynamic>[]},
  };
  Map<String, dynamic> column = <String, dynamic>{
    'result': <String, dynamic>{
      'listRcmInfos': <dynamic>[
        <String, dynamic>{'contentID': 'rec-1', 'contentName': '私享好歌一'},
      ],
    },
  };
  Map<String, dynamic> dailyJson = <String, dynamic>{
    'result': <String, dynamic>{
      'songSimpleInfos': <dynamic>[
        <String, dynamic>{'contentID': 'daily-1', 'contentName': '每日一'},
      ],
    },
  };
  Map<String, dynamic> chartJson = <String, dynamic>{
    'result': <String, dynamic>{
      'songSimpleInfos': <dynamic>[
        <String, dynamic>{'contentID': 'chart-1', 'contentName': '热歌一'},
      ],
    },
  };
  Map<String, dynamic> fmJson = <String, dynamic>{
    'result': <String, dynamic>{
      'listRcmInfos': <dynamic>[
        <String, dynamic>{'contentID': 'fm-1', 'contentName': '电台一'},
      ],
    },
  };
  Map<String, dynamic> playlistJson = <String, dynamic>{
    'result': <String, dynamic>{
      'playListInfos': <dynamic>[
        <String, dynamic>{
          'playListID': 'pl-1',
          'playListName': '推荐歌单一',
          'songNum': 12,
        },
      ],
    },
  };

  @override
  Future<Map<String, dynamic>> get(String path) async {
    gets.add(path);
    if (fail990000Times > 0) {
      fail990000Times--;
      throw const HuaweiException('华为鉴权失败，请重新登录华为账号');
    }
    if (path.startsWith(
      '/music-operation-service/v1/service/page/detail/all',
    )) {
      return home;
    }
    if (path.startsWith(HuaweiAPI.featuredColumnPath)) return column;
    if (path.startsWith(HuaweiAPI.dailyPlaylistPath)) return dailyJson;
    if (path.contains('/chart/detail/bychartid')) return chartJson;
    throw StateError('unexpected get $path');
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic> body = const <String, dynamic>{},
  }) async {
    posts.add('$path ${jsonEncode(body)}');
    if (path.endsWith('/recommend/privatefm')) return fmJson;
    if (path.endsWith('/recommend/playlist')) return playlistJson;
    throw StateError('unexpected post $path');
  }

  @override
  Future<MusicSession> exchangeMusicToken(String accessToken) async {
    musicTokenExchanges++;
    final updated = MusicSession(token: 'new-token', snsUserId: 'user');
    session = updated;
    accountToken = accessToken;
    return updated;
  }
}

Map<String, dynamic> _song(String id, String name) => <String, dynamic>{
  'contentID': id,
  'contentName': name,
  'durationSeconds': 200,
};

Map<String, dynamic> _batch(String id, String label, List<String> names) =>
    <String, dynamic>{
      'contentID': id,
      'contentName': label,
      'listRcmInfos': <dynamic>[
        for (var i = 0; i < names.length; i++) _song('$id-$i', names[i]),
      ],
    };

void main() {
  test('榜单解析只使用真实字段，不生成假名字', () {
    final p = HuaweiAPI.parsePlaylist(<String, dynamic>{
      'chartID': 'chart-real-1',
      'chartName': '真实榜单',
      'picture': 'https://contentcenter-drcn.dbankcdn.cn/img/cover.jpg',
      'songNum': '128',
    });
    expect(p.id, 'chart-real-1');
    expect(p.name, '真实榜单');
    expect(p.songCount, 128);
    expect(p.cover.toString(), contains('contentcenter-drcn.dbankcdn.cn'));
  });

  test('Banner 解析只接受华为图片域名', () {
    final real = HuaweiAPI.parseBanners(<String, dynamic>{
      'columns': <dynamic>[
        <String, dynamic>{
          'picture': 'https://contentcenter-drcn.dbankcdn.cn/img/banner.jpg',
          'title': '真实活动',
          'subTitle': '来自接口',
        },
      ],
    });
    expect(real.length, 1);
    expect(real.first.title, '真实活动');

    final fake = HuaweiAPI.parseBanners(<String, dynamic>{
      'banner': <String, dynamic>{
        'picture': 'https://evil.example.com/banner.jpg',
        'title': '假活动',
      },
    });
    expect(fake, isEmpty);
  });

  test('pmf001 三层结构：childSimpleInfos → listRcmInfos 拆成独立批次', () {
    final d = HuaweiAPI.parseDiscover(<String, dynamic>{
      'result': <String, dynamic>{
        'columnInfoExs': <dynamic>[
          <String, dynamic>{
            'columnInfo': <String, dynamic>{'columnID': 'home'},
            'contentSimpleInfos': <dynamic>[
              <String, dynamic>{
                'contentID': 'pmf001',
                'contentType': '12',
                'contentName': '现在就听',
                'childSimpleInfos': <dynamic>[
                  _batch('heart-batch', 'heart 心动', <String>['心动一', '心动二']),
                  _batch('new-batch', 'new 新歌', <String>['新歌一', '新歌二']),
                  _batch('hot-batch', 'hot 热歌', <String>['热歌一', '热歌二']),
                ],
              },
            ],
          },
        ],
      },
    });

    expect(d.features.any((f) => f.id == 'pmf001'), isTrue);
    expect(
      d.listen.map((s) => s.id),
      containsAll(<String>['heart-batch-0', 'new-batch-0', 'hot-batch-0']),
    );
    expect(d.heart.map((s) => s.id), containsAll(<String>['heart-batch-0']));
    expect(d.newSongs.map((s) => s.id), containsAll(<String>['new-batch-0']));
    expect(d.hot.map((s) => s.id), containsAll(<String>['hot-batch-0']));
    final heartIds = d.heart.map((s) => s.id).toSet();
    final newIds = d.newSongs.map((s) => s.id).toSet();
    final hotIds = d.hot.map((s) => s.id).toSet();
    expect(heartIds.intersection(newIds), isEmpty);
    expect(heartIds.intersection(hotIds), isEmpty);
    expect(newIds.intersection(hotIds), isEmpty);
  });

  test('错误拼写 pfm001 / pfm002 不再触发 pmf001 内嵌批次', () {
    final d = HuaweiAPI.parseDiscover(<String, dynamic>{
      'result': <String, dynamic>{
        'columnInfoExs': <dynamic>[
          <String, dynamic>{
            'contentSimpleInfos': <dynamic>[
              <String, dynamic>{
                'contentID': 'pfm001',
                'contentType': '12',
                'contentName': '错误功能卡',
                'childSimpleInfos': <dynamic>[
                  _batch('bad-1', '错误', <String>['错误歌曲']),
                ],
              },
              <String, dynamic>{
                'contentID': 'pfm002',
                'contentType': '12',
                'contentName': '错误功能卡二',
                'listRcmInfos': <dynamic>[_song('bad-2', '错误歌曲二')],
              },
            ],
          },
        ],
      },
    });
    expect(d.listen, isEmpty);
    expect(d.heart, isEmpty);
    expect(d.newSongs, isEmpty);
    expect(d.hot, isEmpty);
  });

  test('parseDiscover 按真实 contentType 分流，a001 只进 daily', () {
    final d = HuaweiAPI.parseDiscover(<String, dynamic>{
      'result': <String, dynamic>{
        'columnInfoExs': <dynamic>[
          <String, dynamic>{
            'contentSimpleInfos': <dynamic>[
              <String, dynamic>{
                'contentType': '4',
                'contentID': 'a001',
                'contentName': '每日30首',
                'listRcmInfos': <dynamic>[_song('daily-inline', '每日内嵌')],
              },
              <String, dynamic>{
                'contentType': '7',
                'contentID': '24926',
                'chartName': '热歌榜',
              },
              <String, dynamic>{
                'contentType': '2',
                'albumID': 'album-1',
                'albumName': '专辑一',
              },
            ],
          },
        ],
      },
    });
    expect(d.daily.map((s) => s.id), <String>['daily-inline']);
    expect(d.charts.single.id, '24926');
    expect(d.albums.single.id, 'album-1');
    expect(d.recommended, isEmpty);
  });

  test('8011 栏目参数拼装 + 独立返回', () async {
    final gateway = _FakeGateway();
    final api = HuaweiAPI(gateway: gateway);
    final songs = await api.featuredSongs();
    expect(songs.single.id, 'rec-1');
    expect(
      gateway.gets.last,
      contains('columnId=8011&start=0&limit=30&hasRecommend=1'),
    );
  });

  test('a001 / privatefm / recommend playlist / 24926 各自独立请求', () async {
    final gateway = _FakeGateway();
    final api = HuaweiAPI(gateway: gateway);

    final daily = await api.daily30();
    expect(daily.single.id, 'daily-1');
    expect(gateway.gets.last, contains('musicListID=a001'));
    expect(gateway.gets.last, startsWith(HuaweiAPI.dailyPlaylistPath));

    final fm = await api.privateFm(mode: '2');
    expect(fm.single.id, 'fm-1');
    expect(gateway.posts.last, contains('/recommend/privatefm'));
    expect(gateway.posts.last, contains('"rcmMode":"2"'));

    final lists = await api.recommendedPlaylists();
    expect(lists.single.id, 'pl-1');
    expect(lists.single.name, '推荐歌单一');
    expect(gateway.posts.last, contains('/recommend/playlist'));

    final charts = await api.chartSongs(HuaweiAPI.hotChartId);
    expect(charts.single.id, 'chart-1');
    expect(gateway.gets.last, contains('chartID=24926'));
  });

  test('discover 组合各独立来源，daily/recommended/listen 互不冒充', () async {
    final gateway = _FakeGateway();
    gateway.home = <String, dynamic>{
      'result': <String, dynamic>{
        'columnInfoExs': <dynamic>[
          <String, dynamic>{
            'contentSimpleInfos': <dynamic>[
              <String, dynamic>{
                'contentType': '4',
                'contentID': 'a001',
                'contentName': '每日30首',
              },
            ],
          },
        ],
      },
    };
    final api = HuaweiAPI(gateway: gateway);
    final d = await api.discover();
    expect(d.recommended.single.id, 'rec-1');
    expect(d.daily.single.id, 'daily-1');
    expect(d.listen.single.id, 'fm-1');
    expect(d.recommendedColumnId, '8011');
    expect(d.playlists.any((p) => p.id == 'pl-1'), isTrue);
    expect(d.playlists.any((p) => p.id == 'a001'), isTrue);
    expect(d.charts.any((p) => p.id == '24926'), isTrue);
    expect(d.recommended.single.id, isNot(d.daily.single.id));
    expect(d.recommended.single.id, isNot(d.listen.single.id));
  });

  test('990000：一次会话刷新重试 + 30 秒冷却', () async {
    final gateway = _FakeGateway(fail990000Times: 1)..accountToken = 'acc';
    final api = HuaweiAPI(gateway: gateway);
    final songs = await api.daily30();
    expect(songs.single.id, 'daily-1');
    expect(gateway.musicTokenExchanges, 1);

    final failing = _FakeGateway(fail990000Times: 100)..accountToken = 'acc';
    final cooling = HuaweiAPI(gateway: failing);
    await expectLater(cooling.daily30(), throwsA(isA<HuaweiException>()));
    expect(cooling.isAuthCoolingDown, isTrue);
    final exchanges = failing.musicTokenExchanges;
    await expectLater(cooling.daily30(), throwsA(isA<HuaweiException>()));
    expect(failing.musicTokenExchanges, exchanges);
  });

  test('parseSong 解析 artistNamePairs 的歌手名与 ID（REA HomeSongs 字段）', () {
    final s = HuaweiAPI.parseSong(<String, dynamic>{
      'contentID': 'song-with-artist',
      'contentName': '带歌手ID的歌',
      'artistNamePairs': <dynamic>[
        <String, dynamic>{'artistName': '周杰伦', 'artistID': 'artist-jay'},
        <String, dynamic>{'artistName': '潘儿', 'artistID': 'artist-pan'},
      ],
      'durationSeconds': 200,
    });
    expect(s.artists, <String>['周杰伦', '潘儿']);
    expect(s.artistIds, <String>['artist-jay', 'artist-pan']);
    expect(s.durationMs, 200000);
  });

  test('parseSong 在只有精简键时也能工作（ID/NM/pic）', () {
    final s = HuaweiAPI.parseSong(<String, dynamic>{
      'ID': 'compact-1',
      'NM': '精简键歌曲',
      'pic': 'https://contentcenter-drcn.dbankcdn.cn/img/c.jpg',
      'dur': 185000,
    });
    expect(s.id, 'compact-1');
    expect(s.name, '精简键歌曲');
    expect(s.durationMs, 185000);
    expect(s.cover.toString(), contains('dbankcdn.cn'));
  });

  test('parseSong 读取 picture 子对象封面（播放条/歌词页封面）', () {
    final s = HuaweiAPI.parseSong(<String, dynamic>{
      'contentID': 'song-cover',
      'contentName': '有封面的歌',
      'picture': <String, dynamic>{
        'bigImgURL': 'https://contentcenter-drcn.dbankcdn.cn/img/big.jpg',
        'middleImgURL': 'https://contentcenter-drcn.dbankcdn.cn/img/mid.jpg',
        'smallImgURL': 'https://contentcenter-drcn.dbankcdn.cn/img/small.jpg',
      },
    });
    expect(s.cover, isNotNull);
    expect(s.cover.toString(), contains('big.jpg'));
  });

  test('空 DiscoverData 表示接口没有返回，不含占位内容', () {
    const d = DiscoverData();
    expect(d.banners, isEmpty);
    expect(d.newSongs, isEmpty);
    expect(d.playlists, isEmpty);
    expect(d.charts, isEmpty);
    expect(d.radio, isEmpty);
    expect(d.recommended, isEmpty);
    expect(d.listen, isEmpty);
    expect(d.heart, isEmpty);
    expect(d.hot, isEmpty);
    expect(d.daily, isEmpty);
    expect(d.features, isEmpty);
  });

  upstreamQualityTests();
}

void upstreamQualityTests() {
  test('上游音质：网易云 privilege.level 决定档位（非本地写死）', () {
    final q = HuaweiAPI.qualitiesFromUpstream(<String, dynamic>{
      'privilege': <String, dynamic>{'level': 'exhigh'},
    });
    expect(q.contains(AudioQuality.lossless), isTrue);
  });

  test('上游音质：maxbr 码率决定档位（990000 → Hi-Res）', () {
    final q = HuaweiAPI.qualitiesFromUpstream(<String, dynamic>{
      'songPrivilege': <String, dynamic>{'maxbr': 990000},
    });
    expect(q.contains(AudioQuality.hiRes), isTrue);
  });

  test('上游音质：chargeInfoList 付费档位参与判定', () {
    final q = HuaweiAPI.qualitiesFromUpstream(<String, dynamic>{
      'chargeInfoList': <dynamic>[
        <String, dynamic>{'level': 'hires'},
        <String, dynamic>{'level': 'lossless'},
      ],
    });
    expect(q.contains(AudioQuality.hiRes), isTrue);
    expect(q.contains(AudioQuality.lossless), isTrue);
  });

  test('上游无任何档位字段时保守退回标准档', () {
    final q = HuaweiAPI.qualitiesFromUpstream(<String, dynamic>{
      'contentID': 'x',
      'contentName': 'y',
    });
    expect(q, <AudioQuality>{AudioQuality.standard});
  });

  test('上游华为 highestQuality/hiResAvailable/huaweiAudioFiles 决定档位', () {
    final hiRes = HuaweiAPI.qualitiesFromUpstream(<String, dynamic>{
      'hiResAvailable': true,
      'highestQuality': 'hires',
      'huaweiAudioFiles': <String, dynamic>{'types': 110},
    });
    expect(hiRes, contains(AudioQuality.hiRes));
    expect(hiRes, contains(AudioQuality.lossless));

    final sq = HuaweiAPI.qualitiesFromUpstream(<String, dynamic>{
      'hiResAvailable': false,
      'highestQuality': 'sq',
      'huaweiAudioFiles': <String, dynamic>{'types': 14},
    });
    expect(sq, contains(AudioQuality.lossless));
    expect(sq, isNot(contains(AudioQuality.hiRes)));
  });

  test('码率到档位映射遵循网易云 level 体系', () {
    expect(AudioQuality.fromBitrate(128000), AudioQuality.standard);
    expect(AudioQuality.fromBitrate(320000), AudioQuality.lossless);
    expect(AudioQuality.fromBitrate(990000), AudioQuality.hiRes);
  });
}
