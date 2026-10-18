enum PlatformGroup { android, apple, windows, other }

class DirectProfile {
  const DirectProfile({required this.containers, required this.audioCodecs});

  final List<String> containers;
  final List<String> audioCodecs;

  Map<String, dynamic> toJson() => {
    'containers': containers,
    'audioCodecs': audioCodecs,
    'protocols': const ['http'],
  };
}

const aacTranscodeProfile = {
  'container': 'aac',
  'audioCodec': 'aac',
  'protocol': 'http',
  'maxAudioChannels': 2,
};

const maxTranscodeBitrateBps = 256000;
const classicTranscodeBitrateKbps = 256;

List<DirectProfile> directProfiles(PlatformGroup platform) {
  const flac = DirectProfile(containers: ['flac'], audioCodecs: ['flac']);
  const mp3 = DirectProfile(containers: ['mp3'], audioCodecs: ['mp3']);
  const aac = DirectProfile(containers: ['aac', 'm4a', 'mp4'], audioCodecs: ['aac']);
  const wav = DirectProfile(containers: ['wav'], audioCodecs: ['pcm']);
  switch (platform) {
    case PlatformGroup.android:
      return const [
        flac,
        mp3,
        aac,
        DirectProfile(containers: ['ogg', 'opus', 'oga'], audioCodecs: ['opus']),
        DirectProfile(containers: ['ogg', 'oga'], audioCodecs: ['vorbis']),
        wav,
      ];
    case PlatformGroup.apple:
      return const [
        flac,
        DirectProfile(containers: ['m4a', 'mp4'], audioCodecs: ['alac']),
        mp3,
        aac,
        wav,
        DirectProfile(containers: ['aiff', 'aif'], audioCodecs: ['pcm']),
      ];
    case PlatformGroup.windows:
      return const [
        flac,
        mp3,
        aac,
        wav,
        DirectProfile(containers: ['wma', 'asf'], audioCodecs: ['wma']),
      ];
    case PlatformGroup.other:
      return const [flac, mp3, aac, wav];
  }
}

bool suffixCanDirect(PlatformGroup platform, String suffix) {
  final normalized = suffix.toLowerCase().replaceAll('.', '');
  const android = {'flac', 'mp3', 'aac', 'm4a', 'mp4', 'opus', 'ogg', 'oga', 'wav'};
  const apple = {'flac', 'alac', 'm4a', 'mp4', 'mp3', 'aac', 'wav', 'aiff', 'aif'};
  const windows = {'flac', 'mp3', 'aac', 'm4a', 'mp4', 'wav', 'wma', 'asf'};
  final allowed = switch (platform) {
    PlatformGroup.android => android,
    PlatformGroup.apple => apple,
    PlatformGroup.windows => windows,
    PlatformGroup.other => {'flac', 'mp3', 'aac', 'm4a', 'mp4', 'wav'},
  };
  return allowed.contains(normalized);
}

Map<String, dynamic> clientInfoBody({
  required String platformLabel,
  required PlatformGroup platform,
  required bool allowDirect,
}) {
  return {
    'name': 'Habitus',
    'platform': platformLabel,
    'maxTranscodingAudioBitrate': maxTranscodeBitrateBps,
    'directPlayProfiles': allowDirect
        ? directProfiles(platform).map((profile) => profile.toJson()).toList()
        : const <Map<String, dynamic>>[],
    'transcodingProfiles': const [aacTranscodeProfile],
  };
}

bool declaresHls(Map<String, dynamic> body) {
  final encoded = body.toString().toLowerCase();
  return encoded.contains('hls');
}
