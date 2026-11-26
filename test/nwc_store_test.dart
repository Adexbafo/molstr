import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/payments/nwc_cipher.dart';
import 'package:molstr/core/payments/nwc_store.dart';

class _MemorySecretStorage implements NwcSecretStorage {
  String? value;
  String? mode;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async => value = v;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> readMode() async => mode;

  @override
  Future<void> writeMode(String v) async => mode = v;

  @override
  Future<void> deleteMode() async => mode = null;
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
    expect(loaded!.walletPubkey, walletPub);
    await store.clear();
    expect(await store.isConnected(), isFalse);
  });

  test('encryption mode persists', () async {
    final store = NwcStore(secretStorage: _MemorySecretStorage());
    expect(await store.loadEncryption(), NwcEncryption.nip44V2);
    await store.saveEncryption(NwcEncryption.nip04);
    expect(await store.loadEncryption(), NwcEncryption.nip04);
  });
}
