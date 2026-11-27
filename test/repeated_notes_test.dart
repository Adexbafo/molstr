import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/feed_curation.dart';
import 'package:molstr/core/nostr/nostr_event.dart';

void main() {
  final authorKey = List.filled(32, '61').join();
  final otherKey = List.filled(32, '62').join();

  NostrEvent note(String key, String content, int createdAt) {
    return NostrEvent.sign(
      privateKeyHex: key,
      kind: 1,
      content: content,
      createdAt: createdAt,
    );
  }

  test('same author and identical text collapse to the newest copy', () {
    final older = note(authorKey, 'gm', 1700000000);
    final newer = note(authorKey, 'gm', 1700000060);

    final kept = collapseRepeatedNotes([older, newer]);

    expect(kept, hasLength(1));
    expect(kept.single.id, newer.id);
  });

  test('different authors posting the same text are both kept', () {
    final a = note(authorKey, 'gm', 1700000000);
    final b = note(otherKey, 'gm', 1700000001);

    expect(collapseRepeatedNotes([a, b]), hasLength(2));
  });

  test('surrounding whitespace does not make a copy look different', () {
    final a = note(authorKey, 'gm', 1700000000);
    final b = note(authorKey, '  gm\n', 1700000001);

    expect(collapseRepeatedNotes([a, b]), hasLength(1));
  });

  test('different text from the same author is kept', () {
    final a = note(authorKey, 'gm', 1700000000);
    final b = note(authorKey, 'gn', 1700000001);

    expect(collapseRepeatedNotes([a, b]), hasLength(2));
  });
}
