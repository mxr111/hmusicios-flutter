import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../theme.dart';

/// 酷狗登录：原版走 h5.kugou.com 扫码；Flutter 版先提供 Cookie 手动登录，
/// 字段与 KugouSession.fromCookies 对齐（token/userid/dfid/mid）。
class KugouLoginSheet extends StatefulWidget {
  const KugouLoginSheet({super.key, required this.state});

  final AppState state;

  @override
  State<KugouLoginSheet> createState() => _KugouLoginSheetState();
}

class _KugouLoginSheetState extends State<KugouLoginSheet> {
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
      setState(() => _error = '请填入酷狗 Cookie 或 token/userid');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      widget.state.kugou.signInWithCookies(<String, dynamic>{'cookie': text});
      await widget.state.kugou.refreshProfile();
      await widget.state.persistSession();
      if (!mounted) return;
      Navigator.pop(context);
      widget.state.refresh();
      widget.state.loadKugouHome();
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
          const Text('登录酷狗音乐', style: MuyuTheme.section),
          const SizedBox(height: 10),
          const Text(
            '在酷狗网页版/客户端登录后，从开发者工具复制 Cookie，'
            '至少包含 token 与 userid；dfid、mid 可一并粘贴。',
            style: MuyuTheme.muted,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cookie,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Cookie',
              hintText: 'token=...; userid=...; dfid=...; mid=...',
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
