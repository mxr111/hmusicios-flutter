import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// 网易云二维码登录（REA：NewQR / CheckQR，端点 /weapi/login/qrcode/unikey
/// + /weapi/login/qrcode/client/loginQQ）。
class NeteaseLoginSheet extends StatefulWidget {
  const NeteaseLoginSheet({super.key, required this.state});
  final AppState state;

  @override
  State<NeteaseLoginSheet> createState() => _NeteaseLoginSheetState();
}

class _NeteaseLoginSheetState extends State<NeteaseLoginSheet> {
  String? _unikey;
  String _status = '正在获取二维码…';
  String? _error;
  bool _busy = false;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _status = '正在获取二维码…');
    try {
      final key = await widget.state.netease.newQrKey();
      if (!mounted) return;
      setState(() {
        _unikey = key;
        _status = '请用网易云音乐 App 扫码，或打开下方链接登录';
      });
      _poller = Timer.periodic(const Duration(seconds: 3), (_) => _check(key));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _status = '获取二维码失败';
      });
    }
  }

  Future<void> _check(String key) async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await widget.state.netease.checkQr(key);
      if (!mounted) return;
      if (r.status == 803 && r.session != null) {
        _poller?.cancel();
        await widget.state.persistSession();
        if (mounted) Navigator.pop(context);
        widget.state.refresh();
        widget.state.loadHome();
        widget.state.loadLibrary();
        return;
      }
      setState(() {
        _status = switch (r.status) {
          801 => '等待扫码…',
          802 => '已扫码，请在手机上确认',
          800 => '二维码已过期，正在刷新…',
          _ => '等待扫码…',
        };
      });
      if (r.status == 800) {
        _poller?.cancel();
        _start();
      }
    } catch (e) {
      // 轮询中的瞬时错误不打断流程，继续下一次。
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _unikey == null
        ? ''
        : 'https://music.163.com/login?codekey=$_unikey';
    return Padding(
      padding: EdgeInsets.only(
        left: 22,
        right: 22,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('网易云音乐 · 扫码登录', style: MuyuTheme.section),
          const SizedBox(height: 10),
          Text(_status, style: MuyuTheme.muted),
          const SizedBox(height: 16),
          if (_unikey != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MuyuColors.divider),
              ),
              child: Column(
                children: [
                  const Icon(Icons.qr_code_2, size: 96, color: Color(0xFFEF4444)),
                  const SizedBox(height: 10),
                  const Text('二维码登录链接（可复制到浏览器/手机打开）',
                      style: MuyuTheme.muted),
                  const SizedBox(height: 6),
                  SelectableText(url,
                      style: const TextStyle(fontSize: 12, color: MuyuColors.accent)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制链接'),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: url)),
                  ),
                ],
              ),
            ),
          ] else if (_error != null)
            StatePanel(
              message: _error!,
              onRetry: _start,
              actionLabel: '重试',
            )
          else
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(height: 14),
          const Text(
            '或手动填入 MUSIC_U Cookie（已在浏览器登录网易云后，从开发者工具复制）：',
            style: MuyuTheme.muted,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.key),
            label: const Text('手动填入 MUSIC_U'),
            onPressed: () => _showManualCookie(context),
          ),
        ],
      ),
    );
  }

  void _showManualCookie(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('填入 MUSIC_U'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'MUSIC_U=...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim().replaceFirst('MUSIC_U=', '');
              Navigator.pop(ctx);
              if (value.isNotEmpty) {
                widget.state.netease.signInWithCookies(value);
                widget.state.persistSession();
                _poller?.cancel();
                Navigator.pop(context);
                widget.state.refresh();
                widget.state.loadHome();
              }
            },
            child: const Text('登录'),
          ),
        ],
      ),
    );
  }
}
