import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/interactions.dart';
import 'package:molstr/core/nostr/nostr_event.dart';

void main() {
  final key = List.filled(32, '6e').join();

  test('reply to a root note marks it as root', () {
    final parent = NostrEvent.sign(
      privateKeyHex: key,
      kind: 1,
      content: 'root',
      createdAt: 1700000000,
    );
    final tags = Interactions.replyTags(parent);
    expect(tags, contains(equals(['e', parent.id, '', 'root'])));
    expect(tags, contains(equals(['p', parent.pubkey])));
  });

  test('reply to a reply keeps root and marks parent as reply', () {
    final root = NostrEvent.sign(
      privateKeyHex: key,
      kind: 1,
      content: 'root',
      createdAt: 1700000000,
    );
    final reply = NostrEvent.sign(
      privateKeyHex: key,
      kind: 1,
      content: 'reply',
      tags: [
        ['e', root.id, '', 'root'],
        ['p', root.pubkey],
      ],
      createdAt: 1700000100,
    );
    final tags = Interactions.replyTags(reply);
    expect(tags, contains(equals(['e', root.id, '', 'root'])));
    expect(tags, contains(equals(['e', reply.id, '', 'reply'])));
  });
}
