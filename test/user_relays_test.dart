import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/nostr_event.dart';
import 'package:molstr/core/nostr/user_relays.dart';

void main() {
  final key = List.filled(32, 'ab').join();

  NostrEvent relayList(List<List<String>> tags) {
    return NostrEvent.sign(
      privateKeyHex: key,
      kind: kRelayListKind,
      content: '',
      tags: tags,
    );
  }

  test('markerless r tags are both read and write', () {
    final parsed = parseRelayListEvent(relayList([
      ['r', 'wss://relay.primal.net'],
    ]));

    expect(parsed.readRelays, ['wss://relay.primal.net']);
    expect(parsed.writeRelays, ['wss://relay.primal.net']);
  });

  test('read and write markers are respected', () {
    final parsed = parseRelayListEvent(relayList([
      ['r', 'wss://read.example.com', 'read'],
      ['r', 'wss://write.example.com', 'write'],
    ]));

    expect(parsed.readRelays, ['wss://read.example.com']);
    expect(parsed.writeRelays, ['wss://write.example.com']);
  });

  test('invalid, non-wss, and duplicate entries are skipped', () {
    final parsed = parseRelayListEvent(relayList([
      ['r', 'wss://good.example.com'],
      ['r', 'ws://insecure.example.com'],
      ['r', 'not-a-url'],
      ['r', 'wss://good.example.com'],
      ['r', ''],
    ]));

    expect(parsed.readRelays, ['wss://good.example.com']);
    expect(parsed.writeRelays, ['wss://good.example.com']);
  });

  test('wrong kind returns an empty list', () {
    final event = NostrEvent.sign(
      privateKeyHex: key,
      kind: 1,
      content: 'note',
    );
    final parsed = parseRelayListEvent(event);
    expect(parsed.isEmpty, isTrue);
  });

  test('pickLatestRelayList keeps the newest kind-10002 event', () {
    final older = relayList([
      ['r', 'wss://old.example.com'],
    ]);
    // Force a newer timestamp by signing with a later createdAt.
    final newer = NostrEvent.sign(
      privateKeyHex: key,
      kind: kRelayListKind,
      content: '',
      createdAt: older.createdAt + 10,
      tags: [
        ['r', 'wss://new.example.com'],
      ],
    );

    final latest = pickLatestRelayList([older, newer])!;
    expect(latest.readRelays, ['wss://new.example.com']);
  });
}
