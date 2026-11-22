import 'dart:math';

import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'nip19.dart';

class Identity {
  const Identity({
    required this.pubkey,
    required this.npub,
  });

  final String pubkey;
  final String npub;
}

class GeneratedIdentity {
  const GeneratedIdentity({
    required this.identity,
    required this.nsec,
  });

  final Identity identity;
  final String nsec;
}

class IdentityService {
  static const _nsecStorageKey = 'molstr.identity.nsec';

  IdentityService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  GeneratedIdentity generateIdentity() {
    final random = Random.secure();

    for (var attempt = 0; attempt < 20; attempt++) {
      final bytes = List<int>.generate(
        32,
        (_) => random.nextInt(256),
        growable: false,
      );

      final privateKeyHex = Nip19.bytesToHex(bytes);

      try {
        final publicKeyHex = bip340.getPublicKey(privateKeyHex);

        return GeneratedIdentity(
          nsec: Nip19.nsecFromHex(privateKeyHex),
          identity: Identity(
            pubkey: publicKeyHex,
            npub: Nip19.npubFromHex(publicKeyHex),
          ),
        );
      } catch (_) {
        continue;
      }
    }

    throw StateError('Could not generate a valid Nostr key.');
  }

  Future<Identity> saveIdentity(String nsec) async {
    final normalized = nsec.trim();
    final identity = identityFromNsec(normalized);

    await _storage.write(
      key: _nsecStorageKey,
      value: normalized,
    );

    return identity;
  }

  Future<Identity?> currentIdentity() async {
    final nsec = await _storage.read(key: _nsecStorageKey);
    if (nsec == null || nsec.isEmpty) return null;
    return identityFromNsec(nsec);
  }

  Future<void> deleteIdentity() async {
    await _storage.delete(key: _nsecStorageKey);
  }

  Identity identityFromNsec(String nsec) {
    final privateKeyHex = Nip19.hexFromNsec(nsec);
    final publicKeyHex = bip340.getPublicKey(privateKeyHex);

    return Identity(
      pubkey: publicKeyHex,
      npub: Nip19.npubFromHex(publicKeyHex),
    );
  }
}