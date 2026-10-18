import '../copy/zh.dart';

class TranscodeDecision {
  const TranscodeDecision({
    required this.canDirectPlay,
    required this.canTranscode,
    this.transcodeParams,
    this.errorReason,
    this.sourceCodec,
    this.sourceContainer,
    this.transcodeProtocol,
    this.transcodeCodec,
    this.notFound = false,
  });

  final bool canDirectPlay;
  final bool canTranscode;
  final String? transcodeParams;
  final String? errorReason;
  final String? sourceCodec;
  final String? sourceContainer;
  final String? transcodeProtocol;
  final String? transcodeCodec;
  final bool notFound;

  bool get hls => (transcodeProtocol ?? '').toLowerCase() == 'hls';
}

class PlaybackRoute {
  const PlaybackRoute({
    required this.direct,
    required this.useTranscodeStream,
    required this.label,
    required this.codecKey,
    this.transcodeParams,
    this.classicFormat,
    this.maxBitRateKbps,
    this.seekWithOffset = false,
    this.seekWithTimeOffset = false,
  });

  final bool direct;
  final bool useTranscodeStream;
  final String? transcodeParams;
  final String? classicFormat;
  final int? maxBitRateKbps;
  final String label;
  final String codecKey;
  final bool seekWithOffset;
  final bool seekWithTimeOffset;

  String get endpoint => useTranscodeStream ? 'getTranscodeStream' : 'stream';

  Map<String, String> query({required String mediaId, int offsetSeconds = 0}) {
    final params = <String, String>{};
    if (useTranscodeStream) {
      params['mediaId'] = mediaId;
      params['mediaType'] = 'song';
      if (transcodeParams != null && transcodeParams!.isNotEmpty) {
        params['transcodeParams'] = transcodeParams!;
      }
      if (offsetSeconds > 0) params['offset'] = '$offsetSeconds';
    } else {
      params['id'] = mediaId;
      if (classicFormat != null) params['format'] = classicFormat!;
      if (maxBitRateKbps != null) params['maxBitRate'] = '$maxBitRateKbps';
      if (offsetSeconds > 0 && seekWithTimeOffset) {
        params['timeOffset'] = '$offsetSeconds';
      }
    }
    return params;
  }
}

class RouteChoice {
  const RouteChoice._(this.route, {this.notFound = false, this.skip = false});

  final PlaybackRoute? route;
  final bool notFound;
  final bool skip;

  static RouteChoice play(PlaybackRoute route) => RouteChoice._(route);
  static const missing = RouteChoice._(null, notFound: true);
  static const cannot = RouteChoice._(null, skip: true);
}

/// Picks a stream. Navidrome 0.64.2 drops AAC profiles inside
/// getTranscodeDecision, so a decision that cannot transcode falls back to
/// the classic `stream` endpoint with `format=aac` and `maxBitRate=256`.
/// An HLS decision is discarded the same way. `transcodeParams` is copied
/// through and never rebuilt.
RouteChoice chooseRoute({
  required bool hasTranscoding,
  required bool hasTranscodeOffset,
  required bool wantDirect,
  required bool localCanDirect,
  required String suffix,
  required bool forceTranscode,
  TranscodeDecision? decision,
}) {
  final codec = suffix.toLowerCase().replaceAll('.', '');
  if (decision?.notFound == true) return RouteChoice.missing;

  if (!hasTranscoding || decision == null) {
    final direct = wantDirect && localCanDirect && !forceTranscode;
    return RouteChoice.play(_classic(
      direct: direct,
      suffix: codec,
      hasTranscodeOffset: hasTranscodeOffset,
    ));
  }

  if (wantDirect && decision.canDirectPlay && !forceTranscode && !decision.hls) {
    final source = (decision.sourceCodec ?? codec).toUpperCase();
    return RouteChoice.play(
      PlaybackRoute(
        direct: true,
        useTranscodeStream: true,
        transcodeParams: decision.transcodeParams,
        label: source.isEmpty ? Zh.directPlay : '${Zh.directPlay} · $source',
        codecKey: (decision.sourceCodec ?? codec).toLowerCase(),
      ),
    );
  }

  final transcodeUsable =
      decision.canTranscode &&
      !decision.hls &&
      (decision.transcodeParams ?? '').isNotEmpty &&
      (decision.transcodeProtocol == null || decision.transcodeProtocol!.toLowerCase() == 'http');
  if (transcodeUsable && (!wantDirect || !decision.canDirectPlay || forceTranscode)) {
    return RouteChoice.play(
      PlaybackRoute(
        direct: false,
        useTranscodeStream: true,
        transcodeParams: decision.transcodeParams,
        label: Zh.transcodedAac,
        codecKey: (decision.transcodeCodec ?? 'aac').toLowerCase(),
        seekWithOffset: true,
      ),
    );
  }

  if (decision.hls || !decision.canDirectPlay || forceTranscode || !wantDirect) {
    return RouteChoice.play(
      _classic(direct: false, suffix: codec, hasTranscodeOffset: hasTranscodeOffset),
    );
  }

  if (decision.canDirectPlay) {
    final source = (decision.sourceCodec ?? codec).toUpperCase();
    return RouteChoice.play(
      PlaybackRoute(
        direct: true,
        useTranscodeStream: true,
        transcodeParams: decision.transcodeParams,
        label: source.isEmpty ? Zh.directPlay : '${Zh.directPlay} · $source',
        codecKey: (decision.sourceCodec ?? codec).toLowerCase(),
      ),
    );
  }

  return RouteChoice.cannot;
}

PlaybackRoute _classic({
  required bool direct,
  required String suffix,
  required bool hasTranscodeOffset,
}) {
  if (direct) {
    final shown = suffix.isEmpty ? '' : ' · ${suffix.toUpperCase()}';
    return PlaybackRoute(
      direct: true,
      useTranscodeStream: false,
      classicFormat: 'raw',
      label: '${Zh.directPlay}$shown',
      codecKey: suffix,
    );
  }
  return PlaybackRoute(
    direct: false,
    useTranscodeStream: false,
    classicFormat: 'aac',
    maxBitRateKbps: 256,
    label: Zh.transcodedAac,
    codecKey: 'aac',
    seekWithTimeOffset: hasTranscodeOffset,
  );
}

bool sameDirectDecoder(PlaybackRoute? current, PlaybackRoute? next) {
  if (current == null || next == null) return false;
  if (!current.direct || !next.direct) return false;
  if (current.codecKey.isEmpty || next.codecKey.isEmpty) return false;
  return current.codecKey == next.codecKey;
}
