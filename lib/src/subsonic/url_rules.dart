import '../failure.dart';
import '../copy/zh.dart';

class NormalizedUrl {
  const NormalizedUrl({required this.base, required this.http});

  final String base;
  final bool http;
}

NormalizedUrl normalizeBaseUrl(String input) {
  var raw = input.trim();
  if (raw.isEmpty) {
    throw const AppFailure(FailureKind.invalidInput, Zh.invalidUrl);
  }
  if (!raw.contains('://')) raw = 'http://$raw';
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw const AppFailure(FailureKind.invalidInput, Zh.invalidUrl);
  }
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.toLowerCase().endsWith('/rest')) {
    path = path.substring(0, path.length - '/rest'.length);
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
  }
  final port = uri.hasPort ? ':${uri.port}' : '';
  final base = '${uri.scheme}://${uri.host}$port$path';
  return NormalizedUrl(base: base, http: uri.scheme == 'http');
}

String hostLabel(String baseUrl) {
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || uri.host.isEmpty) return baseUrl;
  return uri.host;
}
