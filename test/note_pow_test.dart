import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/nostr_event.dart';
import 'package:molstr/core/nostr/note_pow.dart';
import 'package:flutter/material.dart';
import 'package:molstr/ui/render/note_card.dart';

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

  test('powDifficultyFromTags reads the committed difficulty', () {
    expect(
        powDifficultyFromTags([
          ['nonce', '12', '8'],
        ]),
        8);
    expect(
        powDifficultyFromTags([
          ['t', 'x'],
        ]),
        isNull);
    expect(
        powDifficultyFromTags([
          ['nonce', '1'],
        ]),
        isNull);
  });

  testWidgets('note card shows a proof-of-work badge', (tester) async {
    final event = NostrEvent.sign(
      privateKeyHex: List.filled(32, '11').join(),
      kind: 1,
      content: 'mined note',
      tags: [
        ['nonce', '7', '8'],
      ],
      createdAt: 1700000000,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteCard(
            event: event,
            profile: null,
            provenance: '',
            loadImages: false,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.speed), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
  });
}
