import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/dm_relays.dart';
import 'package:molstr/core/nostr/nostr_event.dart';

void main() {
  final key = List.filled(32, 'ab').join();

  NostrEvent dmList(int kind, List<List<String>> tags) {
    return NostrEvent.sign(
      privateKeyHex: key,
      kind: kind,
      content: '',
      tags: tags,
    );
  }

  test('parses relay tags from a 10050 event', () {
    final event = dmList(
      kDmRelayListKind,
      [
        ['relay', 'wss://relay.damus.io'],
        ['relay', 'wss://nos.lol'],
      ],
    );

    expect(
      parseDmRelayList(event),
      ['wss://relay.damus.io', 'wss://nos.lol'],
    );
  });

  test('skips non-wss, malformed, and duplicate relays', () {
    final event = dmList(
      kDmRelayListKind,
      [
        ['relay', 'wss://good.example.com'],
        ['relay', 'ws://insecure.example.com'],
        ['relay', 'wss://'],
        ['relay', ''],
        ['relay', 'wss://user:pass@secure.example.com'],
        ['relay', 'wss://good.example.com'],
        ['notrelay', 'wss://ignored.example.com'],
      ],
    );

    expect(parseDmRelayList(event), ['wss://good.example.com']);
  });

  test('returns empty for wrong kind', () {
    final event = dmList(1, [
      ['relay', 'wss://nos.lol'],
    ]);

    expect(parseDmRelayList(event), isEmpty);
  });
}
