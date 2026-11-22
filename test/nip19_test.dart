import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/identity_service.dart';
import 'package:molstr/core/nostr/nip19.dart';

void main() {
  test('nsec round trip works', () {
    final hex = List.filled(32, '11').join();
    final nsec = Nip19.nsecFromHex(hex);

    expect(nsec.startsWith('nsec1'), isTrue);
    expect(Nip19.hexFromNsec(nsec), hex);
  });

  test('npub round trip works', () {
    final hex = List.filled(32, '22').join();
    final npub = Nip19.npubFromHex(hex);

    expect(npub.startsWith('npub1'), isTrue);
    expect(Nip19.hexFromNpub(npub), hex);
  });

  test('rejects an nsec used as an npub', () {
    final nsec = Nip19.nsecFromHex(List.filled(32, '33').join());

    expect(
      () => Nip19.hexFromNpub(nsec),
      throwsA(isA<FormatException>()),
    );
  });

  test('generated identity has valid key formats', () {
    final generated = IdentityService().generateIdentity();

    expect(generated.nsec.startsWith('nsec1'), isTrue);
    expect(generated.identity.npub.startsWith('npub1'), isTrue);
    expect(generated.identity.pubkey.length, 64);
  });

  test('matches official NIP-19 npub specification vector', () {
    const pubkeyHex =
        '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';
    const expectedNpub =
        'npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6';

    expect(Nip19.npubFromHex(pubkeyHex), expectedNpub);
    expect(Nip19.hexFromNpub(expectedNpub), pubkeyHex);
  });
}
