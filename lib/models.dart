import 'package:flutter/material.dart';

/// 音质档位：REA 在 Muyu.exe 里观察到 h / sq / hr 三档，
/// 大小字段 size_320mp3 / size_flac / size_hires。
enum AudioQuality {
  standard('h', '标准', 'size_320mp3'),
  lossless('sq', '无损', 'size_flac'),
  hiRes('hr', 'Hi-Res', 'size_hires');

  const AudioQuality(this.code, this.label, this.sizeKey);
  final String code;
  final String label;
  final String sizeKey;

  static AudioQuality fromCode(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'sq':
      case 'flac':
      case 'lossless':
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

class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
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
