import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/payments/nwc_store.dart';

/// In-memory stand-in so tests never touch the platform plugin.
class _MemorySecretStorage implements NwcSecretStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async => value = v;

  @override
  Future<void> delete() async => value = null;
}

void main() {
  final walletPub = bip340.getPublicKey(List.filled(32, 'aa').join());
  final secret = List.filled(32, 'bb').join();
  final testUri = 'nostr+walletconnect://$walletPub'
      '?relay=wss://relay.primal.net&secret=$secret';

  test('save, load round trip, then clear', () async {
    final memory = _MemorySecretStorage();
    final store = NwcStore(secretStorage: memory);

    await store.save(testUri);
    expect(await store.isConnected(), isTrue);

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.walletPubkey, walletPub);
    expect(loaded.secret, secret);
    expect(loaded.relays, ['wss://relay.primal.net']);

    await store.clear();
    expect(await store.isConnected(), isFalse);
    expect(await store.load(), isNull);
    expect(memory.value, isNull);
  });

  test('save rejects an invalid URI and stores nothing', () async {
    final memory = _MemorySecretStorage();
    final store = NwcStore(secretStorage: memory);

    await expectLater(
      store.save('https://not-a-nwc-uri'),
      throwsFormatException,
    );
    expect(memory.value, isNull);
    expect(await store.isConnected(), isFalse);
  });

  test('a corrupted stored value is dropped instead of crashing', () async {
    final memory = _MemorySecretStorage()..value = 'garbage';
    final store = NwcStore(secretStorage: memory);

    expect(await store.load(), isNull);
    expect(memory.value, isNull);
  });
}
