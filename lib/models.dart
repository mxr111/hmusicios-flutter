import 'package:flutter/material.dart';

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
        return AudioQuality.lossless;
      case 'hr':
      case 'hires':
      case 'hi-res':
        return AudioQuality.hiRes;
      default:
        return AudioQuality.standard;
    }
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
    this.cover,
    this.durationMs = 0,
    this.qualities = const <AudioQuality>{AudioQuality.standard},
    this.lyricUrl,
    this.favorite = false,
  });

  final String id;
  final String name;
  final String album;
  final List<String> artists;
  final Uri? cover;
  final int durationMs;
  final Set<AudioQuality> qualities;
  final Uri? lyricUrl;
  bool favorite;

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
  });
  final String id;
  final String name;
  final Uri? cover;
  final int songCount;
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

/// 首页大卡片（截图里的 Music FM / 每日30首 / 心动模式 / 新歌推荐 / 热歌速递）
class HomeCardSpec {
  const HomeCardSpec({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.icon,
    required this.action,
  });
  final String badge;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final IconData icon;
  final String action; // radio / daily / heart / new / hot
}
