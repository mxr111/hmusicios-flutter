import 'package:flutter/material.dart';

/// REA 运行时 + 静态观察得到的沐语主题。
/// Muyu.exe 里明确有「主题为浅色」文案，窗口截图也是浅色：
/// 侧栏浅灰蓝、蓝色竖条选中、白色悬浮播放条、彩色渐变卡片。
/// 深色值取自二进制里同时存在的 #0d0d10 / #141418 / #f3f3f5 一组。
class MuyuColors {
  const MuyuColors._();

  static const Color background = Color(0xFFF6F8FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color sidebar = Color(0xFFE9EDF3);
  static const Color sidebarSelected = Color(0xFFD6E7FB);
  static const Color accent = Color(0xFF548BF0);
  static const Color primary = Color(0xFFE8406A);
  static const Color primarySoft = Color(0xFFFF5D7D);
  static const Color ink = Color(0xFF1B1D22);
  static const Color inkMuted = Color(0xFF8A9099);
  static const Color divider = Color(0xFFE3E7ED);
  static const Color hiRes = Color(0xFFE9A23B);
  static const Color vip = Color(0xFFD4A73F);

  static const Color darkBackground = Color(0xFF0D0D10);
  static const Color darkSurface = Color(0xFF141418);
  static const Color darkInk = Color(0xFFF3F3F5);

  // 首页四张大卡（截图从上到下：深灰 / 淡紫 / 红 / 灰 / 绿）
  static const List<Color> cardNow = [Color(0xFF3C3C41), Color(0xFF17191E)];
  static const List<Color> cardDaily = [Color(0xFFB48AA8), Color(0xFF7C5C86)];
  static const List<Color> cardHeart = [Color(0xFFF33161), Color(0xFFD93F52)];
  static const List<Color> cardNew = [Color(0xFFD9D9DE), Color(0xFFB4A79E)];
  static const List<Color> cardHot = [Color(0xFF609653), Color(0xFF355E2C)];
}

class MuyuTheme {
  const MuyuTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: MuyuColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: MuyuColors.primary,
        brightness: Brightness.light,
      ).copyWith(primary: MuyuColors.primary),
      dividerColor: MuyuColors.divider,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: MuyuColors.ink,
        displayColor: MuyuColors.ink,
      ),
      cardTheme: CardThemeData(
        color: MuyuColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: MuyuColors.darkBackground,
      colorScheme: ColorScheme.fromSeed(
        seedColor: MuyuColors.primary,
        brightness: Brightness.dark,
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: MuyuColors.darkInk),
    );
  }

  static const TextStyle title = TextStyle(
    fontSize: 22, fontWeight: FontWeight.w700, color: MuyuColors.ink);
  static const TextStyle section = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w700, color: MuyuColors.ink);
  static const TextStyle body = TextStyle(fontSize: 13, color: MuyuColors.ink);
  static const TextStyle muted = TextStyle(fontSize: 12, color: MuyuColors.inkMuted);
}

/// 12 款主题：源码事实（tinglan/native/cmd/music/theme.go paletteFor），
/// 每项是 base/surface/text/secondary/muted/accent 六个精确色值。
class MuyuPalette {
  const MuyuPalette({
    required this.name,
    required this.label,
    required this.base,
    required this.surface,
    required this.text,
    required this.secondary,
    required this.muted,
    required this.accent,
    required this.dark,
  });

  final String name;
  final String label;
  final Color base;
  final Color surface;
  final Color text;
  final Color secondary;
  final Color muted;
  final Color accent;
  final bool dark;
}

const List<MuyuPalette> kMuyuPalettes = <MuyuPalette>[
  MuyuPalette(name: 'light', label: '晨光', base: Color(0xFFf1f0ed), surface: Color(0xFFFFFFFF), text: Color(0xFF16181c), secondary: Color(0xFF5c6169), muted: Color(0xFF91969e), accent: Color(0xFFc8202e), dark: false),
  MuyuPalette(name: 'ocean', label: '晴海', base: Color(0xFFeaf1f5), surface: Color(0xFFf6fbff), text: Color(0xFF183247), secondary: Color(0xFF446277), muted: Color(0xFF6c8596), accent: Color(0xFF216b9a), dark: false),
  MuyuPalette(name: 'sage', label: '鼠尾草', base: Color(0xFFeef2e9), surface: Color(0xFFf8fbf4), text: Color(0xFF273a2b), secondary: Color(0xFF566854), muted: Color(0xFF7a8a73), accent: Color(0xFF42784e), dark: false),
  MuyuPalette(name: 'sand', label: '暖砂', base: Color(0xFFf3ece1), surface: Color(0xFFfffaf1), text: Color(0xFF453326), secondary: Color(0xFF75634e), muted: Color(0xFF97836c), accent: Color(0xFFa8622d), dark: false),
  MuyuPalette(name: 'rose', label: '蔷薇', base: Color(0xFFf4e9ed), surface: Color(0xFFfff6f8), text: Color(0xFF442a35), secondary: Color(0xFF775966), muted: Color(0xFF9b7b89), accent: Color(0xFFb0446a), dark: false),
  MuyuPalette(name: 'ice', label: '冰川', base: Color(0xFFe8f2f1), surface: Color(0xFFf4fcfa), text: Color(0xFF203b3a), secondary: Color(0xFF4c706c), muted: Color(0xFF73928e), accent: Color(0xFF197f79), dark: false),
  MuyuPalette(name: 'midnight', label: '午夜蓝', base: Color(0xFF101923), surface: Color(0xFF1b2837), text: Color(0xFFe8eff7), secondary: Color(0xFFbac9dc), muted: Color(0xFF8da1ba), accent: Color(0xFF81b5f5), dark: true),
  MuyuPalette(name: 'forest', label: '深林', base: Color(0xFF101d19), surface: Color(0xFF1d3028), text: Color(0xFFe7f1e9), secondary: Color(0xFFb5cec0), muted: Color(0xFF8ca999), accent: Color(0xFF81cba3), dark: true),
  MuyuPalette(name: 'graphite', label: '石墨', base: Color(0xFF19191c), surface: Color(0xFF29292e), text: Color(0xFFf0efed), secondary: Color(0xFFc4c2c6), muted: Color(0xFF99969f), accent: Color(0xFFe3ae86), dark: true),
  MuyuPalette(name: 'wine', label: '夜玫瑰', base: Color(0xFF21161c), surface: Color(0xFF302129), text: Color(0xFFf7e8ef), secondary: Color(0xFFd4b8c5), muted: Color(0xFFb18d9e), accent: Color(0xFFee99bb), dark: true),
  MuyuPalette(name: 'coffee', label: '咖啡', base: Color(0xFF211c18), surface: Color(0xFF302820), text: Color(0xFFf5ecdf), secondary: Color(0xFFd2bea5), muted: Color(0xFFa68e73), accent: Color(0xFFe7b377), dark: true),
  MuyuPalette(name: 'obsidian', label: '曜石', base: Color(0xFF111314), surface: Color(0xFF1c2022), text: Color(0xFFf0f3f4), secondary: Color(0xFFb9c4c8), muted: Color(0xFF899a9f), accent: Color(0xFFa5d0d7), dark: true),
];

/// 圆角、间距等与截图一致的尺寸常量
class MuyuDims {
  const MuyuDims._();
  static const double sidebarWidth = 208;
  static const double playerBarHeight = 72;
  static const double cardHeight = 258;
  static const double cardWidth = 210;
  static const double radius = 16;
}
