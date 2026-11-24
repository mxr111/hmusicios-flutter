import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';

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

  test('沐语 columnInfoExs 三层结构：pmf001 → childSimpleInfos → listRcmInfos', () {
    final d = HuaweiAPI.parseDiscover(<String, dynamic>{
      'result': <String, dynamic>{
        'columnInfoExs': <dynamic>[
          <String, dynamic>{
            'columnID': 'home',
            'contentSimpleInfos': <dynamic>[
              <String, dynamic>{
                'contentID': 'pmf001',
                'childSimpleInfos': <dynamic>[
                  <String, dynamic>{
                    'listRcmInfos': <dynamic>[
                      <String, dynamic>{
                        'ID': 'radio-real-1',
                        'NM': '真实电台歌曲',
                        'pic': 'https://contentcenter-drcn.dbankcdn.cn/img/r.jpg',
                      },
                    ],
                  },
                ],
              },
              <String, dynamic>{
                'contentID': 'new-songs',
                'songSimpleInfos': <dynamic>[
                  <String, dynamic>{
                    'contentID': 'song-real-1',
                    'contentName': '真实新歌',
                    'middleImgURL': 'https://contentcenter-drcn.dbankcdn.cn/img/s.jpg',
                    'durationSeconds': 210,
                  },
                ],
              },
            ],
          },
        ],
      },
    });
    expect(d.radio.length, 1);
    expect(d.radio.first.id, 'radio-real-1');
    expect(d.radio.first.name, '真实电台歌曲');
    expect(d.newSongs.length, 1);
    expect(d.newSongs.first.id, 'song-real-1');
    expect(d.newSongs.first.name, '真实新歌');
    expect(d.newSongs.first.durationMs, 210000);
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

  test('空 DiscoverData 表示接口没有返回，不含占位内容', () {
    const d = DiscoverData();
    expect(d.banners, isEmpty);
    expect(d.newSongs, isEmpty);
    expect(d.playlists, isEmpty);
    expect(d.charts, isEmpty);
    expect(d.radio, isEmpty);
  });
}
