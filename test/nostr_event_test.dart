import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/nostr_event.dart';
import 'package:molstr/core/nostr/relay_service.dart';

void main() {
  test('signed NostrEvent passes NIP-01 and BIP-340 verification', () {
    final privHex = List.filled(32, '1a').join();
    final event = NostrEvent.sign(
      privateKeyHex: privHex,
      kind: 1,
      content: 'Hello from MolStr!',
      createdAt: 1700000000,
    );

    expect(event.verify(), isTrue);
    expect(NostrEvent.fromJsonVerified(event.toJson()), isNotNull);
  });

  test('tampered content fails verification', () {
    final privHex = List.filled(32, '2b').join();
    final event = NostrEvent.sign(
      privateKeyHex: privHex,
      kind: 1,
      content: 'Original note',
      createdAt: 1700000000,
    );

    final tampered = Map<String, dynamic>.from(event.toJson())
      ..['content'] = 'Forged by untrusted relay';

    expect(NostrEvent.fromJsonVerified(tampered), isNull);
  });

  test('relay URL validation enforces wss for remote relays', () {
    expect(
      RelayService.normalizeRelayUrl('wss://nos.lol/'),
      'wss://nos.lol',
    );
    expect(
      RelayService.normalizeRelayUrl('ws://127.0.0.1:7777/'),
      'ws://127.0.0.1:7777',
    );
    expect(
      () => RelayService.normalizeRelayUrl('ws://nos.lol'),
      throwsA(isA<FormatException>()),
    );
  });
}
