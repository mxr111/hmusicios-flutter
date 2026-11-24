import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// 左侧栏：截图里的用户区 / 主页 / 音乐厅 / 唱片架 / 我的 /
/// 自定义入口 / 本地音乐。选中项有蓝色竖条与浅蓝底。
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.state,
    required this.onSettings,
    this.onLocalMusic,
  });

  final AppState state;
  final VoidCallback onSettings;
  final VoidCallback? onLocalMusic;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MuyuDims.sidebarWidth,
      color: MuyuColors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          _userHeader(),
          const SizedBox(height: 18),
          _item(0, Icons.home_outlined, '主页'),
          _item(2, Icons.music_note_outlined, '音乐厅'),
          _item(3, Icons.album_outlined, '唱片架'),
          _item(4, Icons.person_outline, '我的'),
          const SizedBox(height: 18),
          _customEntry(),
          const SizedBox(height: 6),
          _localMusic(),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TinyIconButton(
              icon: Icons.settings_outlined,
              onTap: onSettings,
              tooltip: '设置',
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _userHeader() {
    final name = state.isLoggedIn ? state.accountName : '土豆';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFF7DFC7), Color(0xFFC28C65)],
              ),
            ),
            child: const Icon(Icons.face, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: MuyuColors.ink)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: MuyuColors.vip.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text('Lv.6',
                          style: TextStyle(
                              fontSize: 9,
                              color: MuyuColors.vip,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.verified, size: 11, color: MuyuColors.accent),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(int index, IconData icon, String label) {
    final selected = state.tab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? MuyuColors.sidebarSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => state.selectTab(index),
          child: Container(
            height: 38,
            padding: const EdgeInsets.only(left: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: selected
                  ? const Border(
                      left: BorderSide(color: MuyuColors.accent, width: 3))
                  : null,
            ),
            child: Row(
              children: [
                Icon(icon,
                    size: 17,
                    color: selected ? MuyuColors.accent : MuyuColors.inkMuted),
                const SizedBox(width: 11),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? MuyuColors.accent : MuyuColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _customEntry() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          const Text('自定义入口',
              style: TextStyle(fontSize: 11, color: MuyuColors.inkMuted)),
          const Spacer(),
          SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.add, size: 15, color: MuyuColors.inkMuted),
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _localMusic() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onLocalMusic,
        child: Container(
          height: 36,
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder_open_outlined,
                  size: 16, color: MuyuColors.inkMuted),
              const SizedBox(width: 11),
              const Text('本地音乐',
                  style: TextStyle(fontSize: 12, color: MuyuColors.inkMuted)),
              const Spacer(),
              if (state.local.songs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('${state.local.songs.length}',
                      style: const TextStyle(
                          fontSize: 11, color: MuyuColors.inkMuted)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
