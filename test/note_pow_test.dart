import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/nostr_event.dart';
import 'package:molstr/core/nostr/note_pow.dart';

void main() {
  test('counts leading zero bits, not hex characters', () {
    expect(leadingZeroBits('0008'.padRight(64, '0')), 12);
    expect(leadingZeroBits('0001'.padRight(64, '0')), 15);
  });

  test('signed note retains the mined ID and committed target', () async {
    final key = List.filled(32, '11').join();
    const content = 'MolStr proof-of-work test';
    const timestamp = 1700000000;

    final author = NostrEvent.sign(
      privateKeyHex: key,
      kind: 1,
      content: content,
      createdAt: timestamp,
    ).pubkey;

    final work = await mineTextNote(
      pubkey: author,
      createdAt: timestamp,
      content: content,
      tags: const [
        ['t', 'molstr'],
      ],
      bits: 4,
    );

    final signed = NostrEvent.sign(
      privateKeyHex: key,
      kind: 1,
      content: content,
      tags: work.tags,
      createdAt: work.createdAt,
    );

    expect(signed.id, work.id);
    expect(signed.verify(), isTrue);
    expect(leadingZeroBits(signed.id), greaterThanOrEqualTo(4));
    expect(signed.tags.last.first, 'nonce');
    expect(signed.tags.last[2], '4');
  });
}
