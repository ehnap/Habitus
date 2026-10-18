class ScrobbleRules {
  static const minimumDuration = Duration(seconds: 30);
  static const fourMinutes = Duration(minutes: 4);

  static bool reached({required Duration duration, required Duration listened}) {
    if (duration < minimumDuration) return false;
    final half = Duration(microseconds: duration.inMicroseconds ~/ 2);
    final threshold = half < fourMinutes ? half : fourMinutes;
    return listened >= threshold;
  }
}

/// Counts time the playhead actually advances. A jump forward is a seek and
/// does not count. Returning to the start opens a new listen.
class ListenClock {
  Duration listened = Duration.zero;
  Duration? lastPosition;
  bool submitted = false;
  int? startedAtMs;
  bool restarted = false;

  void start(int nowMs) {
    listened = Duration.zero;
    lastPosition = null;
    submitted = false;
    startedAtMs = nowMs;
    restarted = false;
  }

  /// Returns true the moment this listen should be submitted.
  bool onPosition({
    required Duration position,
    required Duration duration,
    required bool playing,
    required int nowMs,
  }) {
    restarted = false;
    if (lastPosition != null &&
        position + const Duration(seconds: 2) < lastPosition! &&
        position < const Duration(seconds: 2)) {
      listened = Duration.zero;
      submitted = false;
      startedAtMs = nowMs;
      restarted = true;
    } else if (playing && lastPosition != null) {
      final delta = position - lastPosition!;
      if (delta > Duration.zero && delta <= const Duration(seconds: 5)) {
        listened += delta;
      }
    }
    lastPosition = position;
    if (submitted) return false;
    if (ScrobbleRules.reached(duration: duration, listened: listened)) {
      submitted = true;
      return true;
    }
    return false;
  }
}
