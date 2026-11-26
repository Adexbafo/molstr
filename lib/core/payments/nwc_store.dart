import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'nwc.dart';
import 'nwc_cipher.dart';

abstract class NwcSecretStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
  Future<String?> readMode();
  Future<void> writeMode(String value);
  Future<void> deleteMode();
}

class SecureNwcStorage implements NwcSecretStorage {
  SecureNwcStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _uriKey = 'molstr.nwc.uri';
  static const _encKey = 'molstr.nwc.enc';

  @override
  Future<String?> read() => _storage.read(key: _uriKey);

  @override
  Future<void> write(String value) =>
      _storage.write(key: _uriKey, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _uriKey);

  @override
  Future<String?> readMode() => _storage.read(key: _encKey);

  @override
  Future<void> writeMode(String value) =>
      _storage.write(key: _encKey, value: value);

  @override
  Future<void> deleteMode() => _storage.delete(key: _encKey);
}

class NwcStore {
  NwcStore({NwcSecretStorage? secretStorage})
      : _secret = secretStorage ?? SecureNwcStorage();

  final NwcSecretStorage _secret;

  Future<void> save(String uri) async {
    NwcConnection.parse(uri);
    await _secret.write(uri.trim());
  }

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
    return uri != null && uri.isEmpty == false;
  }

  Future<void> clear() async {
    await _secret.delete();
    await _secret.deleteMode();
  }

  Future<NwcEncryption> loadEncryption() async {
    final v = await _secret.readMode();
    return NwcEncryption.fromStorage(v);
  }

  Future<void> saveEncryption(NwcEncryption mode) =>
      _secret.writeMode(mode.storageValue);
}
