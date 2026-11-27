import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/game_listing.dart';
import 'package:molstr/core/nostr/nostr_event.dart';

void main() {
  final devKey = List.filled(32, '71').join();

  test('parses a NIP-89 game handler', () {
    final devPub = NostrEvent.sign(
      privateKeyHex: devKey,
      kind: 1,
      content: '',
    ).pubkey;

    final event = NostrEvent.sign(
      privateKeyHex: devKey,
      kind: 31990,
      content:
          '{"name":"Nostr Chess","about":"Play chess","picture":"https://example.com/a.png","lud16":"dev@example.com"}',
      tags: [
        ['d', 'nostr-chess'],
        ['t', 'nostr-game'],
        ['web', 'https://example.com/play'],
      ],
      createdAt: 1700000000,
    );

    final game = GameListing.fromEvent(event)!;
    expect(game.d, 'nostr-chess');
    expect(game.name, 'Nostr Chess');
    expect(game.about, 'Play chess');
    expect(game.lud16, 'dev@example.com');
    expect(game.developerPubkey, devPub);
    expect(game.linkFor(TargetPlatform.linux), 'https://example.com/play');
  });

  test('manually added games survive JSON round trip', () {
    final game = GameListing(
      d: 'manual-1',
      name: 'Manual Game',
      about: 'Added by hand',
      developerPubkey: '0' * 64,
      links: const {'web': 'https://example.com'},
      manual: true,
    );

    final restored = GameListing.fromJson(game.toJson())!;
    expect(restored.name, 'Manual Game');
    expect(restored.manual, isTrue);
    expect(restored.links['web'], 'https://example.com');
  });
}
