import 'copy/zh.dart';

enum FailureKind {
  wrongCredentials,
  notAuthorized,
  notFound,
  network,
  certificateUntrusted,
  certificateChanged,
  notNavidrome,
  server,
  secureStore,
  invalidInput,
  cancelled,
}

class AppFailure implements Exception {
  const AppFailure(this.kind, this.message, {this.code, this.fingerprint});

  final FailureKind kind;
  final String message;
  final int? code;
  final String? fingerprint;

  @override
  String toString() => message;
}

String describeError(Object error) {
  if (error is AppFailure) return error.message;
  if (error is FormatException && error.message.isNotEmpty) return error.message;
  return Zh.genericError;
}
