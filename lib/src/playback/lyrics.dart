import '../model/models.dart';

final _lrcStamp = RegExp(r'\[(\d+):(\d{2})(?:[.:](\d{1,3}))?\]');
final _lrcOffset = RegExp(r'\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);

LyricTrack? lyricsFromStructured(Object? lyricsList) {
  if (lyricsList is! Map) return null;
  final raw = lyricsList['structuredLyrics'];
  final entries = <Map<String, dynamic>>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is Map) entries.add(Map<String, dynamic>.from(item));
    }
  } else if (raw is Map) {
    entries.add(Map<String, dynamic>.from(raw));
  }
  if (entries.isEmpty) return null;
  Map<String, dynamic>? chosen;
  for (final entry in entries) {
    if (entry['synced'] == true) {
      chosen = entry;
      break;
    }
  }
  chosen ??= entries.first;
  final synced = chosen['synced'] == true;
  final offsetMs = chosen['offset'] is num ? (chosen['offset'] as num).round() : 0;
  final linesRaw = chosen['line'];
  final lines = <LyricLine>[];
  if (linesRaw is List) {
    for (final line in linesRaw) {
      if (line is! Map) continue;
      final text = line['value']?.toString() ?? '';
      Duration? start;
      if (synced && line['start'] is num) {
        start = Duration(milliseconds: (line['start'] as num).round());
      }
      lines.add(LyricLine(start: start, text: text));
    }
  } else if (linesRaw is Map) {
    final text = linesRaw['value']?.toString() ?? '';
    lines.add(LyricLine(text: text));
  }
  if (lines.isEmpty) return null;
  return LyricTrack(
    synced: synced && lines.any((line) => line.start != null),
    lines: lines,
    offset: Duration(milliseconds: offsetMs),
  );
}

LyricTrack? lyricsFromPlainText(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final offsetMatch = _lrcOffset.firstMatch(value);
  final lrcOffsetMs = offsetMatch == null ? 0 : int.tryParse(offsetMatch.group(1) ?? '') ?? 0;
  final lines = <LyricLine>[];
  for (final rawLine in value.split(RegExp(r'\r?\n'))) {
    final stamps = _lrcStamp.allMatches(rawLine).toList();
    if (stamps.isEmpty) {
      final text = rawLine.trim();
      if (text.isEmpty || text.startsWith('[') && text.endsWith(']')) continue;
      lines.add(LyricLine(text: text));
      continue;
    }
    final text = rawLine.replaceAll(_lrcStamp, '').trim();
    for (final stamp in stamps) {
      final minutes = int.parse(stamp.group(1)!);
      final seconds = int.parse(stamp.group(2)!);
      final fraction = stamp.group(3);
      var millis = 0;
      if (fraction != null) {
        final padded = fraction.padRight(3, '0');
        millis = int.parse(padded.substring(0, 3));
      }
      final start = Duration(minutes: minutes, seconds: seconds, milliseconds: millis) +
          Duration(milliseconds: lrcOffsetMs);
      lines.add(LyricLine(start: start, text: text));
    }
  }
  if (lines.isEmpty) return null;
  final synced = lines.every((line) => line.start != null);
  if (synced) {
    lines.sort((a, b) => a.start!.compareTo(b.start!));
  }
  return LyricTrack(synced: synced, lines: lines);
}

Duration? lineStart(LyricLine line, Duration openSubsonicOffset) {
  if (line.start == null) return null;
  return line.start! - openSubsonicOffset;
}

class LyricWindowLines {
  const LyricWindowLines({required this.current, required this.next});

  final String current;
  final String next;
}

/// The line being sung, and the following line, for the small desktop window.
LyricWindowLines lyricWindowLines(LyricTrack? track, Duration position) {
  if (track == null || track.isEmpty) {
    return const LyricWindowLines(current: '', next: '');
  }
  if (!track.synced) {
    final texts = [
      for (final line in track.lines)
        if (line.text.trim().isNotEmpty) line.text.trim(),
    ];
    return LyricWindowLines(
      current: texts.isEmpty ? '' : texts.first,
      next: texts.length > 1 ? texts[1] : '',
    );
  }
  final index = activeLyricIndex(track, position);
  if (index < 0) {
    return LyricWindowLines(current: '', next: track.lines.first.text.trim());
  }
  final current = track.lines[index].text.trim();
  final next = index + 1 < track.lines.length ? track.lines[index + 1].text.trim() : '';
  return LyricWindowLines(current: current, next: next);
}

int activeLyricIndex(LyricTrack track, Duration position) {
  if (!track.synced) return -1;
  var active = -1;
  for (var i = 0; i < track.lines.length; i++) {
    final start = lineStart(track.lines[i], track.offset);
    if (start == null) continue;
    if (position >= start) {
      active = i;
    } else {
      break;
    }
  }
  return active;
}
