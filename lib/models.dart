import 'package:flutter/material.dart';

/// 歌曲来源平台（沐语实测：收藏页每首歌/每个歌单带来源图标）。
enum MusicSourceLabel {
  huawei('华为', Color(0xFFE8406A), Icons.graphic_eq),
  netease('网易云', Color(0xFF9B2C2C), Icons.cloud_queue),
  kugou('酷狗', Color(0xFF3B82F6), Icons.music_note),
  qq('QQ', Color(0xFFFACC15), Icons.music_note),
  local('本地', Color(0xFF10B981), Icons.folder_open);

  const MusicSourceLabel(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

/// 播放模式：REA 文案观察到「列表循环 / 随机播放 / 单曲」三种。
enum PlayMode {
  listLoop('列表循环', Icons.repeat),
  shuffle('随机播放', Icons.shuffle),
  single('单曲循环', Icons.repeat_one);

  const PlayMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// 音质档位。
/// 源码事实（tinglan/internal/huawei/playback.go）：取流 qualityType
/// "1"=standard(MP3) / "3"=lossless(FLAC)；code 1/3 + codec 判定实际档位。
/// h/sq/hr 是 REA 在 Muyu.exe 静态观察到的显示字段，保留作兼容。
enum AudioQuality {
  standard('h', '标准', 'size_320mp3', '1'),
  lossless('sq', '无损', 'size_flac', '3'),
  hiRes('hr', 'Hi-Res', 'size_hires', '3');

  const AudioQuality(this.code, this.label, this.sizeKey, this.typeCode);
  final String code;
  final String label;
  final String sizeKey;

  /// 取流接口 qualityType 参数（源码事实：只有 1 和 3）。
  final String typeCode;

  static AudioQuality fromCode(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'sq':
      case 'flac':
      case 'lossless':
      case '3':
      // 网易云 level（REA privilege.go 实测档位串）
      case 'exhigh':
      case 'higher':
        return AudioQuality.lossless;
      case 'hr':
      case 'hires':
      case 'hi-res':
      case 'jymaster':
      case 'sky':
        return AudioQuality.hiRes;
      default:
        return AudioQuality.standard;
    }
  }

  /// 从上游码率（br / maxbr，单位 bps）判定档位。
  /// 网易云：128000=标准，320000=极高/无损，990000+=Hi-Res。
  /// 与 EXE 的 songQualities / privilege 映射一致（见 NETEASE_AND_QUALITY_DECOMPILED.md）。
  static AudioQuality fromBitrate(int bps) {
    if (bps >= 900000) return AudioQuality.hiRes;
    if (bps >= 320000) return AudioQuality.lossless;
    return AudioQuality.standard;
  }
}

class HuaweiAudioFile {
  const HuaweiAudioFile({
    required this.quality,
    required this.url,
    required this.sizeBytes,
  });
  final AudioQuality quality;
  final Uri url;
  final int sizeBytes;
}

class Song {
  Song({
    required this.id,
    required this.name,
    this.album = '',
    this.artists = const <String>[],
    this.artistIds = const <String>[],
    this.cover,
    this.durationMs = 0,
    this.qualities = const <AudioQuality>{AudioQuality.standard},
    this.lyricUrl,
    this.favorite = false,
    this.source = MusicSourceLabel.huawei,
    this.member = false,
    this.localPath,
  });

  final String id;
  final String name;
  final String album;
  final List<String> artists;
  /// 歌手 ID（REA 字段 artistID / artistNamePairs.artistID），与 artists 一一对应。
  final List<String> artistIds;
  final Uri? cover;
  final int durationMs;
  final Set<AudioQuality> qualities;
  final Uri? lyricUrl;
  bool favorite;
  final MusicSourceLabel source;

  /// 会员歌曲（沐语收藏页「会员」列的黄色钻石徽标）。
  final bool member;

  /// 本地文件绝对路径；非空时播放器直接读本地文件，不经租约代理。
  final String? localPath;

  String get artistText => artists.isEmpty ? '未知歌手' : artists.join(' / ');

  String get durationText {
    final sec = (durationMs ~/ 1000);
    return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  }
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.cover,
    this.songCount = 0,
    this.kind = '',
  });
  final String id;
  final String name;
  final Uri? cover;
  final int songCount;

  /// 音源插件事实：4=收藏歌单 collected / 5=自建歌单 owned / 7=榜单 chart。
  final String kind;
}

/// 逐字歌词的一个字（源码事实：HMRC `<offset,duration>text`，时间毫秒、
/// offset 相对行首）。time 为绝对秒（行首 + 字偏移）。
class LyricWord {
  const LyricWord(this.time, this.text);
  final Duration time;
  final String text;
}

/// 歌词行：支持行级 LRC 与逐字 HMRC，以及罗马音/翻译副标题。
/// 源码事实：tinglan/internal/lyrics.Line{Time,Text,Translation,Romanization,Words}
class LyricLine {
  const LyricLine(
    this.time,
    this.text, {
    this.words = const <LyricWord>[],
    this.translation = '',
    this.romanization = '',
  });

  final Duration time;
  final String text;
  final List<LyricWord> words;
  final String translation;
  final String romanization;

  bool get hasWords => words.isNotEmpty;

  /// 副标题（罗马音 + 翻译），去重后按阅读顺序（源码 Subtitles()）。
  List<String> get subtitles {
    final out = <String>[];
    for (final value in <String>[romanization, translation]) {
      for (final row in value.split('\n')) {
        final t = row.trim();
        if (t.isNotEmpty && !out.contains(t)) out.add(t);
      }
    }
    return out;
  }
}

/// 评论（REA 26 条 API 中的 /music-sns-service/v1/service/comment/query）。
class Comment {
  const Comment({
    required this.id,
    required this.author,
    required this.content,
    this.avatar,
    this.time = '',
    this.likes = 0,
  });
  final String id;
  final String author;
  final String content;
  final Uri? avatar;
  final String time;
  final int likes;
}

/// 歌手（catalog.Library.Artist / SearchArtists）。
class Artist {
  const Artist({
    required this.id,
    required this.name,
    this.cover,
    this.desc = '',
  });
  final String id;
  final String name;
  final Uri? cover;
  final String desc;
}

/// 首页大卡片（截图里的 Music FM / 每日30首 / 心动模式 / 新歌推荐 / 热歌速递）
class HomeCardSpec {
  const HomeCardSpec({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.icon,
    required this.action,
    this.cover,
  });
  final String badge;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final IconData icon;
  final String action; // radio / daily / heart / new / hot
  final Uri? cover;
}
