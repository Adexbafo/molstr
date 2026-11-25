// ignore_for_file: experimental_member_use

import 'dart:typed_data';

import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/nip19.dart';
import 'package:ndk/shared/nips/nip44/nip44.dart' as nip44;

void main() {
  Future<void> assertVector({
    required String sk1,
    required String sk2,
    required String expectedConversationKey,
    required String nonceHex,
    required String plaintext,
    required String expectedCiphertext,
  }) async {
    // 64-char x-only pubkeys: the exact format MolStr passes to Nip44.
    final pk1 = bip340.getPublicKey(sk1);
    final pk2 = bip340.getPublicKey(sk2);

    final shared12 = nip44.Nip44.computeSharedSecret(sk1, pk2);
    final shared21 = nip44.Nip44.computeSharedSecret(sk2, pk1);
    final conv12 = nip44.Nip44.deriveConversationKey(shared12);
    final conv21 = nip44.Nip44.deriveConversationKey(shared21);

    expect(Nip19.bytesToHex(conv12), expectedConversationKey);
    expect(Nip19.bytesToHex(conv21), expectedConversationKey);

    final ciphertext = await nip44.Nip44.encryptMessage(
      plaintext,
      sk1,
      pk2,
      customNonce: Uint8List.fromList(Nip19.hexToBytes(nonceHex)),
    );
    expect(ciphertext, expectedCiphertext);

    final decrypted = await nip44.Nip44.decryptMessage(
      expectedCiphertext,
      sk2,
      pk1,
    );
    expect(decrypted, plaintext);
  }

  test('NIP-44 v2 vector 001 (ASCII)', () async {
    await assertVector(
      sk1: '0000000000000000000000000000000000000000000000000000000000000001',
      sk2: '0000000000000000000000000000000000000000000000000000000000000002',
      expectedConversationKey:
          'c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d',
      nonceHex:
          '0000000000000000000000000000000000000000000000000000000000000001',
      plaintext: 'a',
      expectedCiphertext:
          'AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABee0G5VSK0/9YypIObAtDKfYEAjD35uVkHyB0F4DwrcNaCXlCWZKaArsGrY6M9wnuTMxWfp1RTN9Xga8no+kF5Vsb',
    );
  });

  test('NIP-44 v2 vector 002 (emoji)', () async {
    await assertVector(
      sk1: '0000000000000000000000000000000000000000000000000000000000000002',
      sk2: '0000000000000000000000000000000000000000000000000000000000000001',
      expectedConversationKey:
          'c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d',
      nonceHex:
          'f00000000000000000000000000000f00000000000000000000000000000000f',
      plaintext: '🍕🫃',
      expectedCiphertext:
          'AvAAAAAAAAAAAAAAAAAAAPAAAAAAAAAAAAAAAAAAAAAPSKSK6is9ngkX2+cSq85Th16oRTISAOfhStnixqZziKMDvB0QQzgFZdjLTPicCJaV8nDITO+QfaQ61+KbWQIOO2Yj',
    );
  });

  test('NIP-44 v2 vector 003 (Unicode CJK/diacritics)', () async {
    await assertVector(
      sk1: '5c0c523f52a5b6fad39ed2403092df8cebc36318b39383bca6c00808626fab3a',
      sk2: '4b22aa260e4acb7021e32f38a6cdf4b673c6a277755bfce287e370c924dc936d',
      expectedConversationKey:
          '3e2b52a63be47d34fe0a80e34e73d436d6963bc8f39827f327057a9986c20a45',
      nonceHex:
          'b635236c42db20f021bb8d1cdff5ca75dd1a0cc72ea742ad750f33010b24f73b',
      plaintext: '表ポあA鷗ŒéＢ逍Üßªąñ丂㐀𠀀',
      expectedCiphertext:
          'ArY1I2xC2yDwIbuNHN/1ynXdGgzHLqdCrXUPMwELJPc7s7JqlCMJBAIIjfkpHReBPXeoMCyuClwgbT419jUWU1PwaNl4FEQYKCDKVJz+97Mp3K+Q2YGa77B6gpxB/lr1QgoqpDf7wDVrDmOqGoiPjWDqy8KzLueKDcm9BVP8xeTJIxs=',
    );
  });

  test('NIP-44 v2 vector 004 (mixed scripts)', () async {
    await assertVector(
      sk1: '8f40e50a84a7462e2b8d24c28898ef1f23359fff50d8c509e6fb7ce06e142f9c',
      sk2: 'b9b0a1e9cc20100c5faa3bbe2777303d25950616c4c6a3fa2e3e046f936ec2ba',
      expectedConversationKey:
          'd5a2f879123145a4b291d767428870f5a8d9e5007193321795b40183d4ab8c2b',
      nonceHex:
          'b20989adc3ddc41cd2c435952c0d59a91315d8c5218d5040573fc3749543acaf',
      plaintext: 'ability🤝的 ȺȾ',
      expectedCiphertext:
          'ArIJia3D3cQc0sQ1lSwNWakTFdjFIY1QQFc/w3SVQ6yvbG2S0x4Yu86QGwPTy7mP3961I1XqB6SFFTzqDZZavhxoWMj7mEVGMQIsh2RLWI5EYQaQDIePSnXPlzf7CIt+voTD',
    );
  });
}
