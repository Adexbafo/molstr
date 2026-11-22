import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/nostr_event.dart';

void main() {
  test('kind 0 profile metadata parses picture, banner and nip05', () {
    final event = NostrEvent.sign(
      privateKeyHex: List.filled(32, '7a').join(),
      kind: 0,
      content:
          '{"name":"Test","picture":"https://example.com/a.png","nip05":"a@b.com","lud16":"a@b.com"}',
      createdAt: 1700000000,
    );
    final profile = ProfileMetadata.fromKind0(event)!;
    expect(profile.picture, 'https://example.com/a.png');
    expect(profile.nip05, 'a@b.com');
    expect(profile.lud16, 'a@b.com');
  });
}
