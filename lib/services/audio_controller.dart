import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import '../protocol/huawei_api.dart';
import 'lease_proxy.dart';

/// 与沐语 MyGo audio.Player 对等：取流 → 租约代理 → 播放器。
class MuyuAudioController extends ChangeNotifier {
  MuyuAudioController(this.api) {
    _player.onPositionChanged.listen((p) {
      position = p;
      notifyListeners();
    });
    _player.onDurationChanged.listen((d) {
      duration = d;
      notifyListeners();
    });
    _player.onPlayerStateChanged.listen((s) {
      playing = s == PlayerState.playing;
      notifyListeners();
    });
    _player.onPlayerComplete.listen((_) => next());
  }

  final HuaweiAPI api;
  final AudioPlayer _player = AudioPlayer();

  Song? current;
  AudioQuality quality = AudioQuality.standard;
  List<Song> queue = <Song>[];
  int index = -1;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool playing = false;
  double volume = 1.0;
  bool shuffle = false;
  String? error;

  /// REA 观察：播放模式为列表循环 / 随机 / 单曲（文案「随机模式播放结束后未继续下一首」）。
  PlayMode playMode = PlayMode.listLoop;

  /// REA 观察：播放器音效 8 种（清晰增强/现场余韵/低频增厚/交响厅堂/近场监听/人声聚焦/环绕漫游）。
  static const List<String> kEffects = <String>[
    '清晰增强', '现场余韵', '低频增厚', '交响厅堂',
    '近场监听', '人声聚焦', '环绕漫游',
  ];
  String effect = '清晰增强';

  /// REA 观察：定时停止（「X 分钟后停止 / 取消定时」）。
  Duration? sleepTimer;
  DateTime? _sleepDeadline;
  Timer? _sleepTicker;

  static const List<AudioQuality> kQualityOrder = <AudioQuality>[
    AudioQuality.hiRes,
    AudioQuality.lossless,
    AudioQuality.standard,
  ];

  Future<void> playSong(Song song, {List<Song>? list}) async {
    if (list != null && list.isNotEmpty) {
      queue = List<Song>.of(list);
      index = queue.indexWhere((s) => s.id == song.id);
      if (index < 0) {
        queue.insert(0, song);
        index = 0;
      }
    } else if (queue.isEmpty) {
      queue = <Song>[song];
      index = 0;
    }
    current = song;
    error = null;
    position = Duration.zero;
    duration = Duration.zero;
    notifyListeners();

    try {
      final files = await api.audioFiles(song.id);
      final wanted = song.qualities.contains(quality)
          ? quality
          : AudioQuality.standard;
      HuaweiAudioFile chosen = files.firstWhere(
        (f) => f.quality == wanted,
        orElse: () => files.first,
      );
      // 切歌前撤销旧租约，避免旧签名 URL 被复用
      LeaseProxy.instance.revoke();
      final local = await LeaseProxy.instance.publish(chosen.url);
      await _player.stop();
      await _player.setVolume(volume);
      await _player.play(UrlSource(local.toString()));
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    if (playing) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  Future<void> seek(Duration to) async {
    await _player.seek(to);
    position = to;
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, 1.0);
    await _player.setVolume(volume);
    notifyListeners();
  }

  Future<void> setQuality(AudioQuality q) async {
    quality = q;
    notifyListeners();
    final song = current;
    if (song != null) await playSong(song, list: queue);
  }

  /// REA 观察：播放模式三态切换（列表循环 / 随机 / 单曲）。
  void cyclePlayMode() {
    playMode = PlayMode.values[(playMode.index + 1) % PlayMode.values.length];
    shuffle = playMode == PlayMode.shuffle;
    notifyListeners();
  }

  void setEffect(String value) {
    if (kEffects.contains(value)) {
      effect = value;
      notifyListeners();
    }
  }

  /// REA 观察：定时停止，X 分钟后暂停（真实定时器，到点暂停播放）。
  void setSleepTimer(int minutes) {
    _sleepTicker?.cancel();
    _sleepTicker = null;
    if (minutes <= 0) {
      sleepTimer = null;
      _sleepDeadline = null;
    } else {
      sleepTimer = Duration(minutes: minutes);
      _sleepDeadline = DateTime.now().add(Duration(minutes: minutes));
      _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        final deadline = _sleepDeadline;
        if (deadline == null) return;
        if (DateTime.now().isAfter(deadline)) {
          _player.pause();
          playing = false;
          sleepTimer = null;
          _sleepDeadline = null;
          _sleepTicker?.cancel();
          _sleepTicker = null;
          notifyListeners();
        } else {
          notifyListeners(); // 刷新剩余时间显示
        }
      });
    }
    notifyListeners();
  }

  Duration? get sleepRemaining {
    final deadline = _sleepDeadline;
    if (deadline == null) return null;
    final left = deadline.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> next() async {
    if (queue.isEmpty) return;
    // REA 观察：单曲循环时播到结尾重播当前曲。
    if (playMode == PlayMode.single && current != null) {
      await playSong(current!, list: queue);
      return;
    }
    final nextIndex = playMode == PlayMode.shuffle
        ? (DateTime.now().millisecondsSinceEpoch % queue.length)
        : (index + 1) % queue.length;
    index = nextIndex;
    await playSong(queue[nextIndex]);
  }

  Future<void> previous() async {
    if (queue.isEmpty) return;
    index = (index - 1 + queue.length) % queue.length;
    await playSong(queue[index]);
  }

  Future<void> stop() async {
    await _player.stop();
    LeaseProxy.instance.revoke();
    playing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sleepTicker?.cancel();
    _player.dispose();
    super.dispose();
  }
}
