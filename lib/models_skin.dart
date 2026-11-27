import 'package:flutter/material.dart';

/// 音源（沐语支持 5 家，本项目接通华为 + 网易云；其余按用户约束未接入）。
enum MusicSource {
  huawei('华为音乐'),
  netease('网易云音乐'),
  kugou('酷狗音乐'),
  qq('QQ音乐');

  const MusicSource(this.label);
  final String label;
}

/// 播放器样式。全屏播放器已收敛为单一经典布局；保留枚举与字段形状，
/// 让设置持久化和旧调用方无需因皮肤减少而改造。
enum PlayerStyle {
  classic('经典播放器', '传统封面 + 歌词列表');

  const PlayerStyle(this.label, this.desc);
  final String label;
  final String desc;
  final IconData icon = Icons.album;
}

/// 歌词排版（REA：LyricAlign / 歌词居中 / 单列双列三列 / 歌词字体 / 粗体）。
enum LyricAlign { left, center }

class LyricStyle {
  const LyricStyle({
    this.align = LyricAlign.left,
    this.bold = true,
    this.columns = 1,
    this.fontScale = 1.0,
    this.font = '鸿蒙黑体',
    this.followCoverColor = true,
  });

  final LyricAlign align;
  final bool bold;
  final int columns; // 桌面歌词 1/2/3 列；播放器内 1/2 列
  final double fontScale;
  final String font;
  final bool followCoverColor;

  LyricStyle copyWith({
    LyricAlign? align,
    bool? bold,
    int? columns,
    double? fontScale,
    String? font,
    bool? followCoverColor,
  }) {
    return LyricStyle(
      align: align ?? this.align,
      bold: bold ?? this.bold,
      columns: columns ?? this.columns,
      fontScale: fontScale ?? this.fontScale,
      font: font ?? this.font,
      followCoverColor: followCoverColor ?? this.followCoverColor,
    );
  }
}

/// 内置字体（REA：「全局、播放器歌词和桌面歌词默认使用鸿蒙黑体」「主歌词与桌面歌词分别支持内置字体选择」）。
const List<String> kBuiltinFonts = <String>['鸿蒙黑体', '系统默认', '思源黑体', '宋体', '楷体'];

/// 沉浸光感档位（REA：「原毛玻璃设置迁移为沉浸光感的超厚档」，
/// 「独立设置按压形变、滑动光效、光感颜色和超薄」）。
enum ImmersiveGlass { thin, normal, thick, ultraThick }

const List<String> kGlassLabels = <String>['超薄', '标准', '厚', '超厚（原毛玻璃）'];

/// 光感颜色（REA：「光感颜色直接从颜色列表选择」「颜色随封面主色变化」）。
const List<Color> kGlowColors = <Color>[
  Color(0xFF548BF0), // 蓝色（沐语默认主题色）
  Color(0xFFE8406A), // 品红
  Color(0xFFE9A23B), // 金
  Color(0xFF35C08E), // 青绿
  Color(0xFF9B6BF0), // 紫
  Color(0xFFF0F0F0), // 白
];
