import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/note_engagement.dart';
import 'package:molstr/core/nostr/nostr_event.dart';

void main() {
  NostrEvent signed(
    String keyByte,
    int kind,
    String content,
    int createdAt, {
    List<List<String>> tags = const [],
  }) {
    return NostrEvent.sign(
      privateKeyHex: List.filled(32, keyByte).join(),
      kind: kind,
      content: content,
      createdAt: createdAt,
      tags: tags,
    );
  }

  test('counts direct replies, likes and reposts without relay duplicates', () {
    final root = signed('11', 1, 'Root note', 1700000000);

    final reply = signed(
      '22',
      1,
      'Direct reply',
      1700000001,
      tags: [
        ['e', root.id, '', 'root'],
      ],
    );

    final nestedReply = signed(
      '33',
      1,
      'Reply to reply',
      1700000002,
      tags: [
        ['e', root.id, '', 'root'],
        ['e', reply.id, '', 'reply'],
      ],
    );

    final like = signed(
      '44',
      7,
      '+',
      1700000003,
      tags: [
        ['e', root.id],
      ],
    );

    final secondLikeFromSameAuthor = signed(
      '44',
      7,
      '+',
      1700000004,
      tags: [
        ['e', root.id],
      ],
    );

    final dislike = signed(
      '55',
      7,
      '-',
      1700000005,
      tags: [
        ['e', root.id],
      ],
    );

    final repost = signed(
      '66',
      6,
      '',
      1700000006,
      tags: [
        ['e', root.id],
      ],
    );

    final counts = tallyNoteEngagement(
      noteIds: [root.id, reply.id],
      verifiedEvents: [
        reply,
        nestedReply,
        like,
        like, // The same event arriving from a second relay.
        secondLikeFromSameAuthor,
        dislike,
        repost,
      ],
    );

    expect(counts[root.id]!.replies, 1);
    expect(counts[root.id]!.likes, 1);
    expect(counts[root.id]!.reposts, 1);

    // A nested reply references the root but directly replies to `reply`.
    expect(counts[reply.id]!.replies, 1);
  });

  test('counts quote notes and groups interacting users', () {
    final target = signed('11', 1, 'Original note', 1700000000);
    final quote = signed(
      '22',
      1,
      'Great point!',
      1700000010,
      tags: [
        ['q', target.id, '', target.pubkey],
        ['p', target.pubkey],
      ],
    );
    final like = signed(
      '33',
      7,
      '+',
      1700000020,
      tags: [
        ['e', target.id],
      ],
    );

    final counts = tallyNoteEngagement(
      noteIds: [target.id],
      verifiedEvents: [quote, like],
    );
    expect(counts[target.id]!.quotes, 1);
    expect(counts[target.id]!.replies, 0);

    final details = buildNoteInteractions(
      targetId: target.id,
      verifiedEvents: [quote, like],
      profiles: const {},
      eventRelays: const {},
      connectedRelays: const ['wss://nos.lol'],
      failedRelays: const [],
    );
    expect(details.quotes.length, 1);
    expect(details.likes.length, 1);
    expect(details.likes.single.pubkey, like.pubkey);
  });

  test('parses zap receipt amount and sums zaps per note', () {
    final target = signed('11', 1, 'Zapped note', 1700000000);
    final zapReceipt = signed(
      '99',
      9735,
      '',
      1700000010,
      tags: [
        ['e', target.id],
        ['p', target.pubkey],
        ['amount', '21000'],
      ],
    );

    final counts = tallyNoteEngagement(
      noteIds: [target.id],
      verifiedEvents: [zapReceipt],
    );

    expect(counts[target.id]!.zapSats, 21);
    expect(formatSats(21), '21');
    expect(formatSats(2500), '2.5k');
    expect(formatSats(1200000), '1.2M');
  });
}
