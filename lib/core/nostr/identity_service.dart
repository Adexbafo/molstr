import 'dart:convert';
import 'dart:math';

import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'nip19.dart';
import 'nostr_event.dart';

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
  static const _legacyNsecStorageKey = 'molstr.identity.nsec';
  static const _activePubkeyStorageKey = 'molstr.active.pubkey';
  static const _accountsListStorageKey = 'molstr.accounts.list';
  static const _nsecPrefix = 'molstr.nsec.';

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

  /// Migrates single-key storage to multi-account format seamlessly.
  Future<void> _migrateLegacy() async {
    final legacyNsec = await _storage.read(key: _legacyNsecStorageKey);
    if (legacyNsec != null && legacyNsec.isNotEmpty) {
      final identity = identityFromNsec(legacyNsec.trim());
      await _storage.write(
        key: '$_nsecPrefix${identity.pubkey}',
        value: legacyNsec.trim(),
      );
      await _storage.write(
        key: _accountsListStorageKey,
        value: jsonEncode([identity.pubkey]),
      );
      await _storage.write(
        key: _activePubkeyStorageKey,
        value: identity.pubkey,
      );
      await _storage.delete(key: _legacyNsecStorageKey);
    }
  }

  Future<List<Identity>> listIdentities() async {
    await _migrateLegacy();
    final rawList = await _storage.read(key: _accountsListStorageKey);
    if (rawList == null || rawList.isEmpty) return const [];

    try {
      final pubkeys = List<String>.from(jsonDecode(rawList));
      return pubkeys
          .map((pk) => Identity(pubkey: pk, npub: Nip19.npubFromHex(pk)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Identity?> currentIdentity() async {
    await _migrateLegacy();
    final activePubkey = await _storage.read(key: _activePubkeyStorageKey);
    if (activePubkey == null || activePubkey.isEmpty) return null;
    return Identity(
      pubkey: activePubkey,
      npub: Nip19.npubFromHex(activePubkey),
    );
  }

  Future<void> switchAccount(String pubkey) async {
    await _storage.write(key: _activePubkeyStorageKey, value: pubkey);
  }

  Future<Identity> saveIdentity(String nsec) async {
    await _migrateLegacy();
    final normalized = nsec.trim();
    final identity = identityFromNsec(normalized);

    await _storage.write(
      key: '$_nsecPrefix${identity.pubkey}',
      value: normalized,
    );

    final existing = await listIdentities();
    final pubkeys = existing.map((i) => i.pubkey).toSet()..add(identity.pubkey);
    await _storage.write(
      key: _accountsListStorageKey,
      value: jsonEncode(pubkeys.toList()),
    );

    await switchAccount(identity.pubkey);
    return identity;
  }

  /// Returns the hex private key for the active account, or null.
  /// Used only for NIP-44 decryption; the value is never logged or cached.
  Future<String?> currentNsecHex() async {
    final active = await currentIdentity();
    if (active == null) return null;
    final nsec = await _storage.read(key: '$_nsecPrefix${active.pubkey}');
    if (nsec == null || nsec.isEmpty) return null;
    return Nip19.hexFromNsec(nsec);
  }

  Future<String?> currentPublicKeyHex() async {
    final active = await currentIdentity();
    return active?.pubkey;
  }

  Future<void> signOut() async {
    await _storage.delete(key: _activePubkeyStorageKey);
  }

  Future<void> removeAccount(String pubkey) async {
    await _storage.delete(key: '$_nsecPrefix$pubkey');
    final existing = await listIdentities();
    final updated =
        existing.where((i) => i.pubkey != pubkey).map((i) => i.pubkey).toList();

    await _storage.write(
      key: _accountsListStorageKey,
      value: jsonEncode(updated),
    );

    final current = await _storage.read(key: _activePubkeyStorageKey);
    if (current == pubkey) {
      if (updated.isNotEmpty) {
        await switchAccount(updated.first);
      } else {
        await signOut();
      }
    }
  }

  Future<void> deleteIdentity() async {
    final active = await currentIdentity();
    if (active != null) {
      await removeAccount(active.pubkey);
    }
  }

  Identity identityFromNsec(String nsec) {
    final privateKeyHex = Nip19.hexFromNsec(nsec);
    final publicKeyHex = bip340.getPublicKey(privateKeyHex);

    return Identity(
      pubkey: publicKeyHex,
      npub: Nip19.npubFromHex(publicKeyHex),
    );
  }

  Future<NostrEvent> signEvent({
    required int kind,
    required String content,
    List<List<String>> tags = const [],
  }) async {
    final active = await currentIdentity();
    if (active == null) {
      throw StateError('No identity connected.');
    }

    final nsec = await _storage.read(key: '$_nsecPrefix${active.pubkey}');
    if (nsec == null || nsec.isEmpty) {
      throw StateError('No private key available for signing.');
    }

    final hex = Nip19.hexFromNsec(nsec);
    return NostrEvent.sign(
      privateKeyHex: hex,
      kind: kind,
      content: content,
      tags: tags,
    );
  }
}
