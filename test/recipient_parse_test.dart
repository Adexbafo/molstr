import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/nip19.dart';
import 'package:molstr/features/messages/messages_page.dart';

void main() {
  final hex = List.filled(32, 'ab').join();

  test('accepts an npub, with or without the nostr: prefix', () {
    final npub = Nip19.npubFromHex(hex);
    expect(parseRecipientPubkey(npub), hex);
    expect(parseRecipientPubkey('  nostr:$npub  '), hex);
  });

  test('accepts a 64-character hex key in any case', () {
    expect(parseRecipientPubkey(hex.toUpperCase()), hex);
  });

  test('refuses a private key', () {
    final nsec = Nip19.nsecFromHex(hex);
    expect(() => parseRecipientPubkey(nsec), throwsFormatException);
  });

  test('refuses damaged or unrelated input', () {
    final npub = Nip19.npubFromHex(hex);
    expect(
      () => parseRecipientPubkey(npub.substring(0, npub.length - 2)),
      throwsFormatException,
    );
    expect(() => parseRecipientPubkey('hello'), throwsFormatException);
    expect(() => parseRecipientPubkey(''), throwsFormatException);
  });
}
