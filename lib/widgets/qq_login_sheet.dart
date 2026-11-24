import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../theme.dart';

/// QQ 音乐登录：原版支持 Web 扫码 + App MQTT 扫码；Flutter 版先提供 Cookie 登录。
/// 必填 `qqmusic_key`（或 `qqmusic_u`）与 `uin`。
class QqLoginSheet extends StatefulWidget {
  const QqLoginSheet({super.key, required this.state});

  final AppState state;

  @override
  State<QqLoginSheet> createState() => _QqLoginSheetState();
}

class _QqLoginSheetState extends State<QqLoginSheet> {
  final TextEditingController _cookie = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _cookie.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final text = _cookie.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请填入 QQ 音乐 Cookie');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      widget.state.qq.signInWithCookies(<String, dynamic>{'cookie': text});
      await widget.state.persistSession();
      if (!mounted) return;
      Navigator.pop(context);
      widget.state.refresh();
      widget.state.loadQqHome();
      widget.state.loadLibrary();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          const Text('登录 QQ 音乐', style: MuyuTheme.section),
          const SizedBox(height: 10),
          const Text(
            '在 y.qq.com 登录后，从开发者工具复制 Cookie，'
            '至少包含 qqmusic_key 与 uin（qqmusic_u、skey 也可）。',
            style: MuyuTheme.muted,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cookie,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Cookie',
              hintText: 'qqmusic_key=...; uin=...;',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _busy ? null : _apply,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('使用 Cookie 登录'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: const TextStyle(color: MuyuColors.primary, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
