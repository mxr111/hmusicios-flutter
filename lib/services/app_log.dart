import 'dart:collection';

/// 轻量环形日志：记录 API/播放/代理关键事件，导出时不含 token 与查询串。
class AppLog {
  AppLog._();

  static const int maxEntries = 2000;
  static final Queue<String> _entries = Queue<String>();

  static void add(String tag, String message) {
    final now = DateTime.now();
    final stamp = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    _entries.addLast('$stamp [$tag] $message');
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
  }

  static String exportText() {
    if (_entries.isEmpty) return 'Hmusic log: empty';
    return 'Hmusic log (${_entries.length} entries)\n'
        '${_entries.join('\n')}\n';
  }

  static void clear() => _entries.clear();
  static int get length => _entries.length;
}
