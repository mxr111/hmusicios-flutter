import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/endpoints.dart';
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
      'next': 106,
      'more': true,
      'refInfo': 'page-ref',
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
    if (path == HuaweiPaths.playlistDetail) return _accountPlaylistsJson;
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

class _HomeDegradeGateway extends HuaweiGateway {
  _HomeDegradeGateway({
    this.chartCount = 200,
    this.emptyFeatured = true,
    this.fmFails = true,
    this.playlistFails = true,
  });

  final int chartCount;
  final bool emptyFeatured;
  final bool fmFails;
  final bool playlistFails;
  final List<String> posts = <String>[];

  Map<String, dynamic> get _homeJson => <String, dynamic>{
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
                for (var i = 0; i < 6; i++) _song('pmf-$i', 'PMF 歌曲 $i'),
              ],
            },
          ],
        },
      ],
    },
  };

  @override
  Future<Map<String, dynamic>> get(String path) async {
    if (path.startsWith(
      '/music-operation-service/v1/service/page/detail/all',
    )) {
      return _homeJson;
    }
    if (path.startsWith(HuaweiAPI.featuredColumnPath)) {
      return <String, dynamic>{
        'result': <String, dynamic>{
          'listRcmInfos': emptyFeatured
              ? <dynamic>[]
              : <dynamic>[_song('rec-1', '为你推荐一')],
        },
      };
    }
    if (path.startsWith(HuaweiAPI.dailyPlaylistPath)) {
      return <String, dynamic>{
        'result': <String, dynamic>{
          'songSimpleInfos': <dynamic>[_song('daily-1', '每日一')],
        },
      };
    }
    if (path.contains('/chart/detail/bychartid')) {
      return <String, dynamic>{
        'result': <String, dynamic>{
          'songSimpleInfos': <dynamic>[
            for (var i = 0; i < chartCount; i++) _song('chart-$i', '热歌 $i'),
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
      if (fmFails) throw const HuaweiException('HTTP 400');
      return <String, dynamic>{
        'result': <String, dynamic>{
          'listRcmInfos': <dynamic>[_song('fm-1', '电台一')],
        },
      };
    }
    if (path.endsWith('/recommend/playlist')) {
      if (playlistFails) throw const HuaweiException('HTTP 400');
      return <String, dynamic>{
        'result': <String, dynamic>{
          'playListInfos': <dynamic>[
            <String, dynamic>{'playListID': 'pl-1', 'playListName': '歌单一'},
          ],
        },
      };
    }
    if (path == HuaweiPaths.playlistDetail) return _accountPlaylistsJson;
    throw StateError('unexpected post $path');
  }
}

/// `favorite/simple/all` 的真实账号歌单响应（recommend/playlist 回退目标）。
final Map<String, dynamic> _accountPlaylistsJson = <String, dynamic>{
  'result': <String, dynamic>{
    'favoriteInfos': <dynamic>[
      <String, dynamic>{
        'contentID': 'library-1',
        'contentName': '真实歌单一',
        'contentType': 4,
      },
    ],
  },
};

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
                'listRcmInfos': <dynamic>[
                  _song('top-0', '顶层现在就听一'),
                  _song('top-1', '顶层现在就听二'),
                ],
                'childSimpleInfos': <dynamic>[
                  _batch('heart-batch', 'heart 心动', <String>['心动一', '心动二']),
                  _batch('new-batch', 'new 新歌', <String>['新歌一', '新歌二']),
                  _batch('hot-batch', 'hot 热歌', <String>['热歌一', '热歌二']),
                  _batch('other-batch', '其它子批次', <String>['其它一']),
                ],
              },
            ],
          },
        ],
      },
    });

    expect(d.features.any((f) => f.id == 'pmf001'), isTrue);
    expect(d.heart.map((s) => s.id), containsAll(<String>['heart-batch-0']));
    expect(d.newSongs.map((s) => s.id), containsAll(<String>['new-batch-0']));
    expect(d.hot.map((s) => s.id), containsAll(<String>['hot-batch-0']));
    expect(d.listen.map((s) => s.id), <String>['top-0', 'top-1']);
    final listenIds = d.listen.map((s) => s.id).toSet();
    final heartIds = d.heart.map((s) => s.id).toSet();
    final newIds = d.newSongs.map((s) => s.id).toSet();
    final hotIds = d.hot.map((s) => s.id).toSet();
    expect(listenIds, <String>{'top-0', 'top-1'});
    expect(listenIds.intersection(heartIds), isEmpty);
    expect(listenIds.intersection(newIds), isEmpty);
    expect(listenIds.intersection(hotIds), isEmpty);
    expect(listenIds, isNot(contains('other-batch-0')));
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

  test('a001 / privateFm 续页 / recommend playlist / 24926 各自独立请求', () async {
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
    expect(gateway.posts.last, contains('"rcmScenario":"1"'));
    expect(gateway.posts.last, contains('"contentCodes":[]'));
    expect(gateway.posts.last, contains('"limit":12'));
    expect(gateway.posts.last, isNot(contains('"termType"')));
    expect(gateway.posts.last, isNot(contains('"scenario"')));
    expect(gateway.posts.last, isNot(contains('"recommendStrategy"')));
    expect(gateway.posts.last, isNot(contains('"countryCode"')));
    expect(gateway.posts.last, isNot(contains('"contentType"')));

    final charts = await api.chartSongs(HuaweiAPI.hotChartId);
    expect(charts.single.id, 'chart-1');
    expect(gateway.gets.last, contains('chartID=24926'));
  });

  test(
    'heartFmFirstPage 使用 decompiled 首屏 body：null/null/21/refInfo，无 next',
    () async {
      final gateway = _FakeGateway();
      final api = HuaweiAPI(gateway: gateway);

      final page = await api.heartFmFirstPage(refInfo: 'behavior-json');

      expect(page.songs.single.id, 'fm-1');
      expect(page.next, '106');
      expect(page.more, isTrue);
      expect(page.mode, 'heart');
      expect(page.rcmScenario, '21');
      expect(gateway.posts.last, contains('/recommend/privatefm'));
      final body = gateway.posts.last;
      expect(body, contains('"cadence":null'));
      expect(body, contains('"rcmMode":null'));
      expect(body, contains('"rcmScenario":"21"'));
      expect(body, contains('"refInfo":"behavior-json"'));
      expect(body, isNot(contains('"next"')));
    },
  );

  test('privateFmPage 保留真实游标字段，wrapper 仍返回歌曲', () async {
    final gateway = _FakeGateway();
    final api = HuaweiAPI(gateway: gateway);

    final page = await api.privateFmPage(
      mode: '2',
      rcmScenario: '21',
      refInfo: 'ref-from-page',
      next: '106',
    );

    expect(page.songs.single.id, 'fm-1');
    expect(page.next, '106');
    expect(page.more, isTrue);
    expect(page.refInfo, 'page-ref');
    expect(page.mode, '2');
    expect(page.rcmScenario, '21');
    final body = gateway.posts.last;
    expect(body, contains('"cadence":""'));
    expect(body, contains('"rcmMode":"2"'));
    expect(body, contains('"rcmScenario":"21"'));
    expect(body, contains('"refInfo":"ref-from-page"'));
    expect(body, isNot(contains('"next"')));

    // 续页游标 next 不在 body：refInfo 为空时映射为 refInfo。
    await api.privateFmPage(next: '106');
    final mapped = gateway.posts.last;
    expect(mapped, contains('"refInfo":"106"'));
    expect(mapped, isNot(contains('"next"')));

    expect((await api.privateFm(mode: '1')).single.id, 'fm-1');
  });

  test('privateFmPage 非法 rcmMode 本地拒绝，不发请求', () async {
    final gateway = _FakeGateway();
    final api = HuaweiAPI(gateway: gateway);

    await expectLater(api.privateFmPage(mode: '4'), throwsArgumentError);
    expect(gateway.posts, isEmpty);
  });

  test('discover 组合各独立来源，daily/recommended/listen 互不冒充', () async {
    final gateway = _FakeGateway();
    gateway.home = <String, dynamic>{
      'result': <String, dynamic>{
        'columnInfoExs': <dynamic>[
          <String, dynamic>{
            'contentSimpleInfos': <dynamic>[
              <String, dynamic>{
                'contentID': 'pmf001',
                'contentType': '12',
                'contentName': '现在就听',
                'listRcmInfos': <dynamic>[_song('home-listen', '首页现在就听')],
              },
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
    expect(d.listen.single.id, 'home-listen');
    expect(
      gateway.posts.any((p) => p.contains('/recommend/privatefm')),
      isFalse,
      reason: '现在就听不再请求 privatefm',
    );
    expect(d.recommendedColumnId, '8011');
    expect(d.playlists.any((p) => p.id == 'pl-1'), isTrue);
    expect(d.playlists.any((p) => p.id == 'a001'), isTrue);
    expect(d.charts.any((p) => p.id == '24926'), isTrue);
    expect(d.recommended.single.id, isNot(d.daily.single.id));
    expect(d.recommended.single.id, isNot(d.listen.single.id));
  });

  test('discover 优先使用 page 里 recom_exclusive 的动态栏目号', () async {
    final gateway = _FakeGateway();
    gateway.home = <String, dynamic>{
      'result': <String, dynamic>{
        'columnInfoExs': <dynamic>[
          <String, dynamic>{
            'columnInfo': <String, dynamic>{
              'columnKey': 'recom_exclusive',
              'columnID': 'dyn-rec',
            },
            'contentSimpleInfos': <dynamic>[],
          },
        ],
      },
    };
    final api = HuaweiAPI(gateway: gateway);
    final d = await api.discover();

    expect(d.recommendedColumnId, 'dyn-rec');
    expect(
      gateway.gets.any(
        (path) => path.contains('columnId=dyn-rec&start=0&limit=30'),
      ),
      isTrue,
    );
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

  test('24926 的 200 首真实榜单只赋给 hot，不跨板块填充空态', () async {
    final gateway = _HomeDegradeGateway();
    final api = HuaweiAPI(gateway: gateway);
    final d = await api.discover();

    expect(d.hot.length, 200);
    expect(d.hot.first.id, 'chart-0');
    final hotChart = d.charts.firstWhere((p) => p.id == '24926');
    expect(hotChart.songCount, 200);

    expect(d.daily.map((s) => s.id), contains('daily-1'));
    expect(d.listen, isNotEmpty);
    expect(d.recommended, isEmpty, reason: '8011 空必须保持空');
    expect(d.heart, isEmpty, reason: '没有心动独立源时必须为空');
    expect(d.newSongs, isEmpty, reason: '没有 contentType=96 / 新歌标签时必须为空');
    expect(d.listen.map((s) => s.id), everyElement(startsWith('pmf-')));
    expect(
      gateway.posts.any((p) => p.contains('/recommend/privatefm')),
      isFalse,
      reason: '现在就听不再请求 privatefm',
    );
    for (final fake in const <String>['998', 'a003', 'a004', 'a006']) {
      expect(<String>[
        for (final group in <List<Song>>[
          d.listen,
          d.daily,
          d.heart,
          d.newSongs,
          d.hot,
          d.recommended,
        ])
          for (final song in group) song.id,
      ], isNot(contains(fake)));
    }
  });

  test('8011 空 / recommend playlist 400 时保持各板块真实空态', () async {
    final gateway = _HomeDegradeGateway(chartCount: 1);
    final api = HuaweiAPI(gateway: gateway);
    final d = await api.discover();

    expect(d.recommended, isEmpty);
    expect(d.listen, isNotEmpty);
    expect(d.heart, isEmpty);
    expect(d.newSongs, isEmpty);
    expect(d.hot.single.id, 'chart-0');
    expect(d.playlists.any((p) => p.id == 'a001'), isTrue);
    expect(
      d.playlists.any((p) => p.id == 'library-1'),
      isTrue,
      reason: 'recommend/playlist 400 只允许回退到真实账号歌单',
    );
    expect(
      gateway.posts.any((p) => p.contains('/recommend/privatefm')),
      isFalse,
      reason: '现在就听不再请求 privatefm',
    );
  });

  test('recommendedPlaylists 400 时直接回退真实账号歌单，不抛给 live probe', () async {
    final api = HuaweiAPI(gateway: _HomeDegradeGateway());

    final lists = await api.recommendedPlaylists();

    expect(lists.single.id, 'library-1');
  });

  test('8011 / recommend playlist 正常时优先真实独立接口', () async {
    final gateway = _HomeDegradeGateway(
      chartCount: 3,
      emptyFeatured: false,
      fmFails: false,
      playlistFails: false,
    );
    final api = HuaweiAPI(gateway: gateway);
    final d = await api.discover();

    expect(d.recommended.first.id, 'rec-1');
    expect(d.listen.length, 6);
    expect(d.listen.first.id, 'pmf-0');
    expect(d.playlists.any((p) => p.id == 'pl-1'), isTrue);
    expect(d.hot.length, 3);
    expect(
      gateway.posts.any((p) => p.contains('/recommend/privatefm')),
      isFalse,
      reason: '现在就听不再请求 privatefm',
    );
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
