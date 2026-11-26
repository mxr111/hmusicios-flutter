import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import '../models_skin.dart';
import '../protocol/huawei_api.dart';
import '../protocol/kugou_api.dart';
import '../protocol/netease_api.dart';
import '../protocol/qq_api.dart';
import 'app_log.dart';
import 'lease_proxy.dart';
import 'playback_clock.dart';

/// 与沐语 MyGo audio.Player 对等：取流 → 租约代理 → 播放器。
class MuyuAudioController extends ChangeNotifier {
  MuyuAudioController(this.api,
      {NeteaseApi? netease, KugouApi? kugou, QqApi? qq})
      : netease = netease ?? NeteaseApi(),
        kugou = kugou ?? KugouApi(),
        qq = qq ?? QqApi() {
    _player.onPositionChanged.listen((p) {
      if (!_activePlayback || _startingPlayback) return;
      _clock.sync(p, playing: _clock.isPlaying);
      _publishPosition();
      // 高频进度只通知进度条；歌词用 Ticker 自行外推到屏幕刷新率，
      // 不再让整棵 widget 树跟着播放器事件重建。
    });
    _player.onDurationChanged.listen((d) {
      if (_startingPlayback && _acceptStartingDuration) {
        _pendingDuration = d;
      } else if (_activePlayback) {
        _applyDuration(d);
      }
    });
    _player.onPlayerStateChanged.listen((s) {
      if (_activePlayback && !_startingPlayback) {
        _setPlaying(s == PlayerState.playing);
      }
    });
    _player.onPlayerComplete.listen((_) {
      if (!_activePlayback || _startingPlayback) return;
      _activePlayback = false;
      _setPlaying(false);
      next();
    });
  }

  final HuaweiAPI api;
  final NeteaseApi netease;
  final KugouApi kugou;
  final QqApi qq;
  MusicSource source = MusicSource.huawei;
  final AudioPlayer _player = AudioPlayer();

  Song? current;
  /// 与沐语 `quality: hires` 一致：默认请求上游最高档；实际档位由
  /// `playSong` 根据该歌曲上游可用档位回退，不会强行把每首歌降成 MP3。
  AudioQuality quality = AudioQuality.hiRes;
  List<Song> queue = <Song>[];
  int index = -1;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool get playing => _clock.isPlaying;

  /// 低频进度通知（播放器回调频率），仅给进度条等轻量组件监听。
  final ValueNotifier<Duration> positionNotifier =
      ValueNotifier<Duration>(Duration.zero);
  final PlaybackClock _clock = PlaybackClock();
  bool _activePlayback = false;
  bool _startingPlayback = false;
  bool _acceptStartingDuration = false;
  Duration? _pendingDuration;
  int _trackGeneration = 0;
  Future<void> _playerQueue = Future<void>.value();

  /// 歌词校准偏移：正值让歌词提前，负值让歌词延后。
  Duration lyricOffset = Duration.zero;
  static const Duration maxLyricOffset = Duration(seconds: 5);

  /// 高频歌词位置：单调时钟外推，不受系统时间调整/加载延迟影响。
  Duration get displayPosition => _clock.position;
  Duration get lyricPosition => _clock.adjusted(lyricOffset);

  void _setPlaying(bool next) {
    final wasPlaying = _clock.isPlaying;
    final previousPosition = _clock.position;
    _clock.setPlaying(next);
    _publishPosition();
    if (wasPlaying != next || previousPosition != position) {
      notifyListeners();
    }
  }

  void _publishPosition() {
    position = _clock.position;
    positionNotifier.value = position;
  }

  void _applyDuration(Duration value) {
    duration = value < Duration.zero ? Duration.zero : value;
    _clock.duration = duration;
    // duration 更新时 PlaybackClock 会同步夹紧锚点；进度条也立刻同步，
    // 避免歌词时钟与低频位置通知暂时落在不同范围。
    _publishPosition();
    notifyListeners();
  }

  Future<void> _enqueuePlayerOperation(
    Future<void> Function() operation,
  ) {
    final result = _playerQueue.then((_) => operation());
    _playerQueue = result.catchError((Object _) {});
    return result;
  }

  void adjustLyricOffset(Duration delta) {
    lyricOffset =
        PlaybackClock.clampOffset(lyricOffset + delta, limit: maxLyricOffset);
    notifyListeners();
  }

  void resetLyricOffset() {
    lyricOffset = Duration.zero;
    notifyListeners();
  }
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

  /// 默认选用户/沐语设置的档位；该歌曲没有这个档位时，选上游能提供的
  /// 最高档。默认 quality 是 hiRes，因此新会话默认拿最高可播档。
  static AudioQuality chooseQuality(
    AudioQuality requested,
    Iterable<AudioQuality> supported,
  ) {
    final set = supported.toSet();
    if (set.isEmpty) return requested;
    if (set.contains(requested)) return requested;
    return set.reduce((a, b) => a.index > b.index ? a : b);
  }

  Future<void> playSong(Song song, {List<Song>? list}) async {
    final generation = ++_trackGeneration;
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
    _activePlayback = false;
    _startingPlayback = false;
    _acceptStartingDuration = false;
    _pendingDuration = null;
    _clock.duration = Duration.zero;
    _clock.reset(Duration.zero);
    position = Duration.zero;
    duration = Duration.zero;
    positionNotifier.value = Duration.zero;
    notifyListeners();

    try {
      // 先串行停止旧曲，加载期间忽略旧播放器迟到的位置/时长/状态回调。
      await _enqueuePlayerOperation(() async {
        if (generation == _trackGeneration) await _player.stop();
      });
      if (generation != _trackGeneration) return;

      // 本地音乐：直接播放沙箱文件，不需要签名 / 租约代理。
      final localPath = song.localPath;
      if (localPath != null && localPath.isNotEmpty) {
        LeaseProxy.instance.revoke();
        await _enqueuePlayerOperation(() async {
          if (generation != _trackGeneration) return;
          _startingPlayback = true;
          _acceptStartingDuration = false;
          _pendingDuration = null;
          await _player.setVolume(volume);
          _acceptStartingDuration = true;
          await _player.play(DeviceFileSource(localPath));
          _finishStartingPlayback(generation);
        });
        return;
      }
      // 档位由上游决定：把 Song 从上游字段解析出的档位集合传给取流层。
      final List<HuaweiAudioFile> files = switch (source) {
        MusicSource.netease => await netease.audioFiles(song, quality: quality),
        MusicSource.kugou => await kugou.audioFiles(song),
        MusicSource.qq => await qq.audioFiles(song),
        MusicSource.huawei =>
          await api.audioFiles(song.id, upstreamQualities: song.qualities),
      };
      if (files.isEmpty) {
        throw StateError('该音源未返回可播放地址');
      }
      if (generation != _trackGeneration) return;
      final supported = files.isNotEmpty ? files.map((f) => f.quality).toSet() : song.qualities;
      final wanted = chooseQuality(quality, supported);
      HuaweiAudioFile chosen = files.firstWhere(
        (f) => f.quality == wanted,
        orElse: () => files.first,
      );
      AppLog.add(
        'play',
        '${song.name} [${song.id}] ${chosen.quality.name} '
        '${chosen.url.scheme}://${chosen.url.host}${chosen.url.path}',
      );
      final local = await LeaseProxy.instance.publish(chosen.url);
      if (generation != _trackGeneration) return;
      await _enqueuePlayerOperation(() async {
        if (generation != _trackGeneration) return;
        _startingPlayback = true;
        _acceptStartingDuration = false;
        _pendingDuration = null;
        await _player.setVolume(volume);
        _acceptStartingDuration = true;
        await _player.play(UrlSource(local.toString()));
        _finishStartingPlayback(generation);
      });
    } catch (e) {
      if (generation != _trackGeneration) return;
      _startingPlayback = false;
      _acceptStartingDuration = false;
      _activePlayback = false;
      error = e.toString();
      AppLog.add('play', 'error ${song.name} [${song.id}]: $e');
      notifyListeners();
    }
  }

  void _finishStartingPlayback(int generation) {
    _startingPlayback = false;
    _acceptStartingDuration = false;
    if (generation != _trackGeneration) {
      _pendingDuration = null;
      return;
    }
    _activePlayback = true;
    final pendingDuration = _pendingDuration;
    _pendingDuration = null;
    if (pendingDuration != null) {
      duration = pendingDuration < Duration.zero
          ? Duration.zero
          : pendingDuration;
      _clock.duration = duration;
      _publishPosition();
    }
    _setPlaying(true);
  }

  Future<void> toggle() async {
    final generation = _trackGeneration;
    await _enqueuePlayerOperation(() async {
      if (generation != _trackGeneration || !_activePlayback) return;
      final shouldPause = _clock.isPlaying;
      if (shouldPause) {
        await _player.pause();
      } else {
        await _player.resume();
      }
      if (generation == _trackGeneration) _setPlaying(!shouldPause);
    });
  }

  Future<void> seek(Duration to) async {
    final generation = _trackGeneration;
    final previousPosition = _clock.position;
    _clock.seek(to);
    _publishPosition();
    notifyListeners();
    try {
      await _enqueuePlayerOperation(() async {
        if (generation == _trackGeneration && _activePlayback) {
          await _player.seek(_clock.position);
        }
      });
    } catch (_) {
      if (generation == _trackGeneration) {
        _clock.seek(previousPosition);
        _publishPosition();
        notifyListeners();
      }
      rethrow;
    }
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
          final generation = _trackGeneration;
          _enqueuePlayerOperation(() async {
            if (generation == _trackGeneration && _activePlayback) {
              await _player.pause();
              if (generation == _trackGeneration) _setPlaying(false);
            }
          }).catchError((Object _) {});
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
    final generation = ++_trackGeneration;
    _activePlayback = false;
    _startingPlayback = false;
    _acceptStartingDuration = false;
    _pendingDuration = null;
    LeaseProxy.instance.revoke();
    _clock.duration = Duration.zero;
    _clock.reset(Duration.zero);
    position = Duration.zero;
    duration = Duration.zero;
    positionNotifier.value = Duration.zero;
    notifyListeners();
    await _enqueuePlayerOperation(() async {
      if (generation == _trackGeneration) await _player.stop();
    });
  }

  @override
  void dispose() {
    _sleepTicker?.cancel();
    positionNotifier.dispose();
    _player.dispose();
    super.dispose();
  }
}
