import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/qq_api.dart';
import 'package:muyu_flutter/protocol/qq_gateway.dart';

void main() {
  test('zzcSign 与 Muyu 固定向量一致', () {
    expect(
      QqGateway.zzcSign('abc'),
      'zzc163db6e8l6noj1uu5ylcp8kabaw6rnxos4b998e04e',
    );
  });

  test('Cookie 会话识别 qqmusic_key / uin / skey 并显示昵称', () {
    final api = QqApi();
    api.signInWithCookies(<String, dynamic>{
      'qqmusic_key': 'token',
      'uin': 'o0012345678',
      'nickname': '测试用户',
    });
    expect(api.isLoggedIn, isTrue);
    expect(api.displayName, '测试用户');
    expect(api.gateway.session?.uin, '0012345678');

    api.signOut();
    expect(api.isLoggedIn, isFalse);
    expect(api.displayName, 'QQ 音乐');
  });

  test('搜索解析 data.song.list 的 songmid/歌手/专辑/时长/音质', () {
    final songs = QqApi.parseSearch(<String, dynamic>{
      'code': 0,
      'data': <String, dynamic>{
        'song': <String, dynamic>{
          'list': <dynamic>[
            <String, dynamic>{
              'songmid': '0039MnYb0qxYhV',
              'songname': '晴天',
              'albumname': '叶惠美',
              'albummid': '000MkMni19ClKG',
              'interval': 269,
              'size128': 100,
              'size320': 200,
              'sizeflac': 300,
              'size_hires': 400,
              'singer': <dynamic>[
                <String, dynamic>{'mid': '0025NhlN2yWrP4', 'name': '周杰伦'},
              ],
              'pay': <String, dynamic>{'payplay': 1},
            },
            <String, dynamic>{'songname': '缺少 mid 的假歌'},
          ],
        },
      },
    });

    expect(songs.length, 1);
    final song = songs.single;
    expect(song.id, '0039MnYb0qxYhV');
    expect(song.name, '晴天');
    expect(song.album, '叶惠美');
    expect(song.artistText, '周杰伦');
    expect(song.artistIds, <String>['0025NhlN2yWrP4']);
    expect(song.durationMs, 269000);
    expect(song.source, MusicSourceLabel.qq);
    expect(song.member, isTrue);
    expect(song.qualities, contains(AudioQuality.standard));
    expect(song.qualities, contains(AudioQuality.lossless));
    expect(song.qualities, contains(AudioQuality.hiRes));
    expect(
      song.cover.toString(),
      'https://y.gtimg.cn/music/photo_new/T002R800x800M000000MkMni19ClKG.jpg',
    );
  });

  test('歌单与首页响应兼容 tracks / songInfoList 及 file 音质字段', () {
    final tracks = QqApi.parsePlaylistSongs(<String, dynamic>{
      'req_1': <String, dynamic>{
        'code': 0,
        'data': <String, dynamic>{
          'tracks': <dynamic>[
            <String, dynamic>{
              'mid': '001abc',
              'name': '夜曲',
              'interval': 226,
              'singer': <dynamic>[
                <String, dynamic>{'mid': '0025NhlN2yWrP4', 'name': '周杰伦'},
              ],
              'album': <String, dynamic>{
                'mid': '000albumMid',
                'name': '十一月的萧邦',
              },
              'file': <String, dynamic>{
                'size_128mp3': 10,
                'size_320mp3': 20,
                'size_flac': 30,
                'size_hires': 40,
              },
              'pay': <String, dynamic>{'pay_play': 1},
            },
          ],
        },
      },
    });
    expect(tracks.single.id, '001abc');
    expect(tracks.single.album, '十一月的萧邦');
    expect(tracks.single.qualities, contains(AudioQuality.hiRes));

    final home = QqApi.parsePlaylistSongs(<String, dynamic>{
      'req_0': <String, dynamic>{
        'code': 0,
        'data': <String, dynamic>{
          'songInfoList': <dynamic>[
            <String, dynamic>{
              'mid': '002home',
              'name': '七里香',
              'interval': 299,
              'singer': <dynamic>[
                <String, dynamic>{'mid': '0025NhlN2yWrP4', 'name': '周杰伦'},
              ],
              'album': <String, dynamic>{'mid': '000homeAlbum', 'name': '七里香'},
              'file': <String, dynamic>{'size_128mp3': 10},
            },
          ],
        },
      },
    });
    expect(home.single.id, '002home');
    expect(home.single.name, '七里香');
  });

  test('歌单列表解析 dirName/dirId/songNum', () {
    final playlists = QqApi.parsePlaylists(<String, dynamic>{
      'req_1': <String, dynamic>{
        'code': 0,
        'data': <String, dynamic>{
          'info': <dynamic>[
            <String, dynamic>{
              'tid': 123456,
              'dirId': 201,
              'dirName': '我喜欢的音乐',
              'songNum': 42,
              'picUrl': 'https://y.gtimg.cn/cover.jpg',
            },
          ],
        },
      },
    });
    expect(playlists.single.id, '123456');
    expect(playlists.single.name, '我喜欢的音乐');
    expect(playlists.single.songCount, 42);
    expect(playlists.single.kind, 'owned');
  });

  test('歌词支持 base64、翻译 tran 与多时间标签', () {
    final lyric = base64Encode(
      utf8.encode('[00:01.00]第一句\n[00:03.50]第二句\n[00:05.00][00:06.00]重复句'),
    );
    final trans = base64Encode(
      utf8.encode('[00:01.00]First\n[00:03.50]Second'),
    );
    final lines = QqApi.parseLyrics(<String, dynamic>{
      'lyric': lyric,
      'tran': trans,
    });
    expect(lines.length, 4);
    expect(lines.first.text, '第一句');
    expect(lines.first.translation, 'First');
    expect(lines[1].translation, 'Second');
    expect(lines[2].text, '重复句');
    expect(lines[3].text, '重复句');
  });

  test('评论解析 hot_comment + comment 并容错字段别名', () {
    final comments = QqApi.parseComments(<String, dynamic>{
      'code': 0,
      'hot_comment': <String, dynamic>{
        'commentlist': <dynamic>[
          <String, dynamic>{
            'commentid': '1',
            'rootcommentcontent': '热门评论',
            'user': <String, dynamic>{
              'nick': '小明',
              'avatarurl': 'https://y.gtimg.cn/avatar.jpg',
            },
            'time': '2026-11-24',
            'praisenum': 99,
          },
        ],
      },
      'comment': <String, dynamic>{
        'commentlist': <dynamic>[
          <String, dynamic>{
            'commentId': '2',
            'content': '普通评论',
            'nick': '小红',
            'avatar': 'https://y.gtimg.cn/avatar2.jpg',
            'likedCount': 3,
          },
          <String, dynamic>{'commentid': '3', 'content': ''},
        ],
      },
    });
    expect(comments.length, 2);
    expect(comments.first.author, '小明');
    expect(comments.first.likes, 99);
    expect(comments.last.content, '普通评论');
  });

  test('Vkey 构造包含四档 m4a/flac/hires，URL 使用 sip[0]', () {
    final files = QqApi.vkeyFilenames('001abc');
    expect(files.length, 4);
    expect(files, contains('C400001abc001abc.m4a'));
    expect(files, contains('C600001abc001abc.m4a'));
    expect(files, contains('F000001abc001abc.flac'));
    expect(files, contains('RS01001abc001abc.flac'));

    final module = QqApi.buildVkeyModule(
      '001abc',
      uin: '123456',
      guid: '1000000000',
      filenames: files,
    );
    expect(module['module'], 'music.vkey.GetVkey');
    expect(module['method'], 'UrlGetVkey');
    final param = module['param'] as Map<String, dynamic>;
    expect(param['uin'], '123456');
    expect((param['songmid'] as List<dynamic>).length, 4);
    expect((param['filename'] as List<dynamic>).length, 4);
    expect(param['guid'], '1000000000');

    expect(
      QqApi.resolveVkeyUrl(<String>[
        'https://isure.stream.qqmusic.qq.com/',
      ], '/M500001abc001abc.mp3'),
      'https://isure.stream.qqmusic.qq.com/M500001abc001abc.mp3',
    );
    expect(
      QqApi.resolveVkeyUrl(<String>[], '/C400001abc001abc.m4a'),
      'https://isure.stream.qqmusic.qq.com/C400001abc001abc.m4a',
    );
  });

  test('图片 URL 来自 y.gtimg.cn 真实模板', () {
    expect(
      QqGateway.imageUrlForAlbumMid('000MkMni19ClKG'),
      'https://y.gtimg.cn/music/photo_new/T002R800x800M000000MkMni19ClKG.jpg',
    );
  });
}
