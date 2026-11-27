import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/nostr_event.dart';
import 'package:molstr/core/nostr/nostr_lists.dart';
import 'package:molstr/core/nostr/pinned_notes.dart';

void main() {
  final ownerKey = List.filled(32, '3a').join();
  final strangerKey = List.filled(32, '4b').join();
  final owner = bip340.getPublicKey(ownerKey);

  NostrEvent pinList(int kind, List<List<String>> tags) {
    return NostrEvent.sign(
      privateKeyHex: ownerKey,
      kind: kind,
      content: '',
      tags: tags,
      createdAt: 1700000000,
    );
  }

  NostrEvent note(String key, String text, int at, {int kind = 1}) {
    return NostrEvent.sign(
      privateKeyHex: key,
      kind: kind,
      content: text,
      createdAt: at,
    );
  }

  test('newest pin comes first; duplicates, bad ids and other tags are skipped',
      () {
    final a = List.filled(32, 'aa').join();
    final b = List.filled(32, 'bb').join();
    final c = List.filled(32, 'cc').join();

    final ids = pinnedIdsFromList(
      pinList(kPinListKind, [
        ['e', a],
        ['t', 'nostr'],
        ['e', b],
        ['e', 'not-a-hex-id'],
        ['e', a],
        ['e', c],
      ]),
    );

    expect(ids, [c, a, b]);
  });

  test('a pin list is capped at the display limit', () {
    final tags = [
      for (var i = 1; i <= 12; i++) ['e', i.toRadixString(16).padLeft(64, '0')],
    ];

    final ids = pinnedIdsFromList(pinList(kPinListKind, tags));

    expect(ids, hasLength(maxPinnedNotes));
    expect(ids.first, 12.toRadixString(16).padLeft(64, '0'));
  });

  test('an event of another kind is not treated as a pin list', () {
    final a = List.filled(32, 'aa').join();

    expect(
      pinnedIdsFromList(
        pinList(1, [
          ['e', a],
        ]),
      ),
      isEmpty,
    );
  });

  test('only the owner\'s notes are kept, in pin order', () {
    final first = note(ownerKey, 'first', 1700000001);
    final second = note(ownerKey, 'second', 1700000002);
    final poll = note(ownerKey, 'a poll', 1700000003, kind: 1068);
    final foreign = note(strangerKey, 'not mine', 1700000004);
    final reaction = note(ownerKey, '+', 1700000005, kind: 7);
    final missing = List.filled(32, 'ee').join();

    final ordered = orderPinned(
      owner: owner,
      orderedIds: [
        second.id,
        foreign.id,
        missing,
        reaction.id,
        poll.id,
        first.id,
      ],
      events: [first, second, poll, foreign, reaction],
    );

    expect(ordered.map((e) => e.id), [second.id, poll.id, first.id]);
  });
}
