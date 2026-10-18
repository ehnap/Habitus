import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../copy/zh.dart';
import '../failure.dart';

abstract class CredentialStore {
  Future<void> write(String libraryId, String secret);
  Future<String?> read(String libraryId);
  Future<void> delete(String libraryId);
}

class MemoryCredentialStore implements CredentialStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String libraryId) async {
    values.remove(libraryId);
  }

  @override
  Future<String?> read(String libraryId) async => values[libraryId];

  @override
  Future<void> write(String libraryId, String secret) async {
    values[libraryId] = secret;
  }
}

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String libraryId, String secret) async {
    try {
      await _storage.write(key: _key(libraryId), value: secret);
    } catch (_) {
      throw const AppFailure(FailureKind.secureStore, Zh.secureStoreUnavailable);
    }
  }

  @override
  Future<String?> read(String libraryId) async {
    try {
      return await _storage.read(key: _key(libraryId));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> delete(String libraryId) async {
    try {
      await _storage.delete(key: _key(libraryId));
    } catch (_) {
      // The library row is still removed. A leftover secret cannot be used
      // without the record that points at this key.
    }
  }

  String _key(String libraryId) => 'habitus.library.$libraryId';
}
