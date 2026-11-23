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

/// 圆角、间距等与截图一致的尺寸常量
class MuyuDims {
  const MuyuDims._();
  static const double sidebarWidth = 208;
  static const double playerBarHeight = 72;
  static const double cardHeight = 258;
  static const double cardWidth = 210;
  static const double radius = 16;
}
