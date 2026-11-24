import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/netease_api.dart';
import 'package:muyu_flutter/services/app_state.dart';

void main() {
  test('网易云首页轮播解析真实字段并容错', () {
    final banners = NeteaseApi.parseBanners(<String, dynamic>{
      'banners': <dynamic>[
        <String, dynamic>{
          'title': '网易云音乐推荐',
          'imageUrl': 'https://p1.music.126.net/a.jpg',
          'targetId': '123',
        },
        <String, dynamic>{'pic': 'https://p1.music.126.net/b.jpg'},
        <String, dynamic>{},
      ],
    });

    expect(banners.length, 2);
    expect(banners.first.title, '网易云音乐推荐');
    expect(banners.first.imageUrl.toString(), 'https://p1.music.126.net/a.jpg');
    expect(banners.last.title, '网易云推荐');
  });

  test('网易云首页歌单卡解析 trackCount 与封面', () {
    final playlist = NeteaseApi.parsePlaylist(<String, dynamic>{
      'id': 987654321,
      'name': '每日推荐歌单',
      'coverImgUrl': 'https://p2.music.126.net/cover.jpg',
      'trackCount': 42,
    });

    expect(playlist.id, '987654321');
    expect(playlist.name, '每日推荐歌单');
    expect(playlist.songCount, 42);
    expect(playlist.cover.toString(), 'https://p2.music.126.net/cover.jpg');
  });

  test('独家放送卡解析文案与封面', () {
    final specials = NeteaseApi.parseSpecials(<dynamic>[
      <String, dynamic>{
        'id': 12,
        'name': '超级面对面',
        'copywriter': '编辑推荐',
        'picUrl': 'https://p2.music.126.net/special.jpg',
      },
    ]);

    expect(specials.single.title, '超级面对面');
    expect(specials.single.subtitle, '编辑推荐');
    expect(specials.single.cover.toString(), 'https://p2.music.126.net/special.jpg');
  });

  test('推荐新歌解析不会把专辑/歌手对象误判成歌曲', () {
    final songs = NeteaseApi.parseSongs(<String, dynamic>{
      'result': <dynamic>[
        <String, dynamic>{
          'id': 100,
          'name': '外层卡片',
          'picUrl': 'https://p1.music.126.net/card.jpg',
          'song': <String, dynamic>{
            'id': 100,
            'name': '真实歌曲',
            'artists': <dynamic>[
              <String, dynamic>{'id': 9, 'name': '歌手'},
            ],
            'album': <String, dynamic>{'id': 8, 'name': '专辑'},
          },
        },
      ],
    });

    expect(songs.length, 1);
    expect(songs.single.name, '真实歌曲');
    expect(songs.single.artistText, '歌手');
  });

  test('华为/网易云首页数据不共用缓存：合并推荐流按 ID 去重', () {
    final a = Song(id: '1', name: 'A');
    final b = Song(id: '2', name: 'B');
    final merged = AppState.mergeSongs(<List<Song>>[
      <Song>[a, b],
      <Song>[a],
    ]);

    expect(merged.map((s) => s.name), <String>['A', 'B']);
  });
}
