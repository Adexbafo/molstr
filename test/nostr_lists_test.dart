import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/nostr_lists.dart';

void main() {
  final noteId = List.filled(32, 'ab').join();
  final otherId = List.filled(32, 'cd').join();

  test('adding a note keeps every unrelated tag', () {
    final tags = [
      ['t', 'nostr'],
      ['a', '30023:abc:article'],
      ['e', otherId],
    ];
    final next = toggleEventTag(tags, noteId, add: true);

    expect(next, hasLength(4));
    expect(next, contains(equals(['t', 'nostr'])));
    expect(next, contains(equals(['a', '30023:abc:article'])));
    expect(eventIdsIn(next), containsAll([noteId, otherId]));
  });

  test('removing a note removes only that note', () {
    final tags = [
      ['e', noteId],
      ['e', otherId],
    ];
    final next = toggleEventTag(tags, noteId, add: false);

    expect(eventIdsIn(next), {otherId});
  });

  test('adding the same note twice does not duplicate it', () {
    final once = toggleEventTag(const [], noteId, add: true);
    final twice = toggleEventTag(once, noteId, add: true);

    expect(twice, hasLength(1));
  });

  test('private items round-trip when encrypted to your own key', () async {
    final key = List.filled(32, '1a').join();
    final pub = bip340.getPublicKey(key);

    final content = await encryptPrivateTags([
      ['e', noteId],
    ], key, pub);
    final back = await decryptPrivateTags(content, key, pub);

    expect(back, [
      ['e', noteId],
    ]);
  });

  test('older NIP-04 list content is reported as unreadable', () async {
    final key = List.filled(32, '1a').join();
    final pub = bip340.getPublicKey(key);

    expect(await decryptPrivateTags('abc==?iv=def==', key, pub), isNull);
  });
}
