import 'dart:math' as math;

/// ReplayGain applied to the player volume. Positive gain is capped at unity.
/// A peak above full scale pulls the volume down so the result stays at or
/// under 0 dBFS. Missing values leave the volume unchanged.
double replayGainVolume({double? gainDb, double? peak}) {
  if (gainDb == null && (peak == null || peak <= 0)) return 1;
  var linear = gainDb == null ? 1.0 : math.pow(10, gainDb / 20).toDouble();
  if (gainDb != null && gainDb > 0) linear = 1;
  if (peak != null && peak > 0) {
    final limit = 1.0 / peak;
    if (linear > limit) linear = limit;
  }
  if (linear > 1) linear = 1;
  if (linear < 0) return 0;
  if (linear.isNaN || linear.isInfinite) return 1;
  return linear;
}

double? gainForTrack({
  required bool enabled,
  required bool direct,
  required bool albumContext,
  double? trackGain,
  double? albumGain,
  double? trackPeak,
  double? albumPeak,
}) {
  if (!enabled || !direct) return 1;
  final gain = albumContext ? albumGain : trackGain;
  final peak = albumContext ? albumPeak : trackPeak;
  if (gain == null && peak == null) return 1;
  return replayGainVolume(gainDb: gain, peak: peak);
}
