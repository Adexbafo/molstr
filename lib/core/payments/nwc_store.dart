import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'nwc.dart';

/// Just the three operations we need from secure storage.
/// An interface lets us test [NwcStore] without a platform plugin.
abstract class NwcSecretStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// Production storage: the OS keychain / Secret Service via flutter_secure_storage.
class SecureNwcStorage implements NwcSecretStorage {
  SecureNwcStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _uriKey = 'molstr.nwc.uri';

  @override
  Future<String?> read() => _storage.read(key: _uriKey);

  @override
  Future<void> write(String value) =>
      _storage.write(key: _uriKey, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _uriKey);
}

/// Persists the active NWC connection. The secret lives only in secure
/// storage; invalid stored URIs are dropped rather than crashing the app.
class NwcStore {
  NwcStore({NwcSecretStorage? secretStorage})
      : _secret = secretStorage ?? SecureNwcStorage();

  final NwcSecretStorage _secret;

  Future<void> save(String uri) async {
    // Validate before storing anything.
    NwcConnection.parse(uri);
    await _secret.write(uri.trim());
  }

  /// Returns null when nothing is stored or the stored URI is invalid.
  Future<NwcConnection?> load() async {
    final uri = await _secret.read();
    if (uri == null || uri.isEmpty) return null;
    try {
      return NwcConnection.parse(uri);
    } catch (_) {
      await _secret.delete();
      return null;
    }
  }

  Future<bool> isConnected() async {
    final uri = await _secret.read();
    return uri != null && uri.isNotEmpty;
  }

  Future<void> clear() async {
    await _secret.delete();
  }
}
