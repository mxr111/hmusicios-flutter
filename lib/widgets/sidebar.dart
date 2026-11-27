import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// 左侧栏：华为音乐单账号 + 主页 / 音乐厅 / 唱片架 / 我的 /
/// 自定义入口 / 本地音乐。选中项有蓝色竖条与浅蓝底。
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.state,
    required this.onSettings,
    this.onLocalMusic,
    this.onAccount,
  });

  final AppState state;
  final VoidCallback onSettings;
  final VoidCallback? onLocalMusic;
  final VoidCallback? onAccount;

  @override
  Widget build(BuildContext context) {
    final pal = state.palette;
    return Container(
      width: MuyuDims.sidebarWidth,
      color: pal.surface,
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
          _customEntry(context),
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
    final pal = state.palette;
    // 侧栏固定读取华为账号，不跟随底层多平台 source 状态显示其他账号。
    final loggedIn = state.api.isLoggedIn;
    final name = loggedIn
        ? (state.api.displayName ?? '华为音乐用户')
        : '登录华为音乐';
    final avatar = state.api.avatarUrl ?? '';
    const subtitle = '华为音乐账号';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: loggedIn ? '华为音乐账号' : '登录华为音乐',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onAccount,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Row(
                children: [
                  if (avatar.isEmpty)
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: pal.accent.withValues(alpha: 0.14),
                      ),
                      child: Icon(
                        Icons.person_outline,
                        size: 20,
                        color: pal.accent,
                      ),
                    )
                  else
                    CoverArt(
                      url: Uri.tryParse(avatar),
                      size: 36,
                      circle: true,
                      seed: 5,
                    ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: pal.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: loggedIn && state.api.isMember
                                      ? MuyuColors.vip.withValues(alpha: 0.18)
                                      : pal.accent.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: loggedIn && state.api.isMember
                                        ? MuyuColors.vip
                                        : pal.muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (loggedIn && state.api.isMember)
                              const Icon(
                                Icons.verified,
                                size: 11,
                                color: MuyuColors.accent,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(int index, IconData icon, String label) {
    final selected = state.tab == index;
    final pal = state.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color:
            selected ? pal.accent.withValues(alpha: 0.14) : Colors.transparent,
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
                      left: BorderSide(color: MuyuColors.accent, width: 3),
                    )
                  : null,
            ),
            child: Row(
              children: [
                Icon(icon, size: 17, color: selected ? pal.accent : pal.muted),
                const SizedBox(width: 11),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? pal.accent : pal.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _customEntry(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          const Text(
            '自定义入口',
            style: TextStyle(fontSize: 11, color: MuyuColors.inkMuted),
          ),
          const Spacer(),
          SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.add, size: 15, color: MuyuColors.inkMuted),
              onPressed: () {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('自定义入口将在后续版本开放')));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _localMusic() {
    final pal = state.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onLocalMusic,
        child: Container(
          height: 36,
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            color: pal.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.folder_open_outlined, size: 16, color: pal.muted),
              const SizedBox(width: 11),
              Text('本地音乐', style: TextStyle(fontSize: 12, color: pal.muted)),
              const Spacer(),
              if (state.local.songs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${state.local.songs.length}',
                    style: TextStyle(fontSize: 11, color: pal.muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
