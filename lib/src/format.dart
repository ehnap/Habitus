String formatClock(Duration value) {
  final clamped = value < Duration.zero ? Duration.zero : value;
  final total = clamped.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$mm:$ss';
  return '$minutes:$ss';
}

String formatFingerprint(String hex) {
  final clean = hex.replaceAll(':', '').toLowerCase();
  final parts = <String>[];
  for (var i = 0; i < clean.length; i += 2) {
    final end = i + 2 > clean.length ? clean.length : i + 2;
    parts.add(clean.substring(i, end));
  }
  return parts.join(':').toUpperCase();
}
