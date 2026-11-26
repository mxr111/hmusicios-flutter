/// 单调播放时钟：把播放器一次低频 position 样本锚定到 Stopwatch 上，
/// 歌词层再用 Ticker 逐帧外推。避免 DateTime 墙钟变化、切歌加载阶段
/// 提前跑歌词、暂停/恢复时位置跳变。
class PlaybackClock {
  PlaybackClock({Duration Function()? elapsed})
      : _elapsed = elapsed ?? _monotonicElapsed;

  static final Stopwatch _monotonic = Stopwatch()..start();

  static Duration _monotonicElapsed() => _monotonic.elapsed;

  final Duration Function() _elapsed;
  Duration _anchorElapsed = Duration.zero;
  Duration _anchorPosition = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  bool get isPlaying => _playing;
  Duration get duration => _duration;

  set duration(Duration value) {
    final nextDuration = value < Duration.zero ? Duration.zero : value;
    if (nextDuration == _duration) return;

    // 时长更新可能发生在播放过程中。先把当前单调时钟位置固定下来，
    // 再应用新的边界，避免缩短时长后 positionNotifier 仍留在旧位置。
    _anchorPosition = _clamp(position, duration: nextDuration);
    _anchorElapsed = _elapsed();
    _duration = nextDuration;
  }

  /// 当前播放位置；播放中按单调时钟外推，暂停时冻结。
  Duration get position => _clamp(
        _playing
            ? _anchorPosition + _elapsedDelta()
            : _anchorPosition,
      );

  /// 歌词专用位置：在真实播放位置上叠加用户校准偏移。
  Duration adjusted(Duration offset) => _clamp(position + offset);

  /// 播放器回调新的真实位置时重新锚定，保留当前播放/暂停状态。
  void sync(Duration playerPosition, {required bool playing}) {
    _anchorPosition = _clamp(playerPosition);
    _anchorElapsed = _elapsed();
    _playing = playing;
  }

  void setPlaying(bool next) {
    // 播放器状态流可能重复发出相同状态；重复的 playing 不能不断重锚，
    // 否则会让单调时钟跟着事件频率走，而不是跟随真实时间。
    if (next == _playing) return;
    if (_playing) {
      // 先冻结到当前外推位置，再改变状态，避免暂停瞬间倒退。
      _anchorPosition = position;
    }
    _anchorElapsed = _elapsed();
    _playing = next;
  }

  void seek(Duration to) => sync(to, playing: _playing);

  void reset([Duration to = Duration.zero]) {
    _anchorPosition = _clamp(to);
    _anchorElapsed = _elapsed();
    _playing = false;
  }

  Duration _elapsedDelta() {
    final delta = _elapsed() - _anchorElapsed;
    return delta < Duration.zero ? Duration.zero : delta;
  }

  static Duration clampOffset(
    Duration value, {
    Duration limit = const Duration(seconds: 5),
  }) {
    final safeLimit = limit < Duration.zero ? Duration.zero : limit;
    if (value > safeLimit) return safeLimit;
    if (value < -safeLimit) return -safeLimit;
    return value;
  }

  Duration _clamp(Duration value, {Duration? duration}) {
    if (value < Duration.zero) return Duration.zero;
    final maxDuration = duration ?? _duration;
    if (maxDuration > Duration.zero && value > maxDuration) return maxDuration;
    return value;
  }
}
