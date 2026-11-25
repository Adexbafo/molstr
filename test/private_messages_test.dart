// ignore_for_file: experimental_member_use

import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/nostr_event.dart';
import 'package:molstr/core/nostr/private_messages.dart';
import 'package:ndk/shared/nips/nip44/nip44.dart' as nip44;

void main() {
  // Disposable keys for tests only. Never use a real account here.
  final aliceKey = List.filled(32, '1a').join();
  final bobKey = List.filled(32, '2b').join();
  final eveKey = List.filled(32, '3c').join();

  final alicePub = bip340.getPublicKey(aliceKey);
  final bobPub = bip340.getPublicKey(bobKey);
  final evePub = bip340.getPublicKey(eveKey);

  const now = 1700000000;
  const twoDays = 2 * 24 * 60 * 60;

  Future<List<NostrEvent>> aliceWritesToBob(String text) {
    return wrapPrivateMessage(
      senderPrivateKeyHex: aliceKey,
      senderPubkey: alicePub,
      recipients: [bobPub],
      content: text,
      nowSeconds: now,
    );
  }

  NostrEvent wrapAddressedTo(List<NostrEvent> wraps, String pubkey) {
    return wraps.firstWhere(
      (wrap) => wrap.tags.any((tag) => tag[0] == 'p' && tag[1] == pubkey),
    );
  }

  test('ndk NIP-44 cipher round-trips and hides text from others', () async {
    final ciphertext =
        await nip44.Nip44.encryptMessage('hello', aliceKey, bobPub);

    expect(
      await nip44.Nip44.decryptMessage(ciphertext, bobKey, alicePub),
      'hello',
    );

    String? opened;
    try {
      opened = await nip44.Nip44.decryptMessage(ciphertext, eveKey, alicePub);
    } catch (_) {
      opened = null;
    }
    expect(opened, isNot('hello'));
  });

  test('the recipient opens the message and sees the true author', () async {
    final wraps = await aliceWritesToBob('hi bob');
    expect(wraps, hasLength(2));

    final message = await unwrapPrivateMessage(
      giftWrap: wrapAddressedTo(wraps, bobPub),
      myPrivateKeyHex: bobKey,
      myPubkey: bobPub,
    );

    expect(message, isNotNull);
    expect(message!.content, 'hi bob');
    expect(message.senderPubkey, alicePub);
    expect(message.recipients, [bobPub]);
    expect(message.partnerFor(bobPub), alicePub);
  });

  test('the sender can open their own copy', () async {
    final wraps = await aliceWritesToBob('hi bob');

    final message = await unwrapPrivateMessage(
      giftWrap: wrapAddressedTo(wraps, alicePub),
      myPrivateKeyHex: aliceKey,
      myPubkey: alicePub,
    );

    expect(message, isNotNull);
    expect(message!.content, 'hi bob');
    expect(message.partnerFor(alicePub), bobPub);
  });

  test('an outsider cannot open a message addressed to someone else', () async {
    final wraps = await aliceWritesToBob('hi bob');

    final message = await unwrapPrivateMessage(
      giftWrap: wrapAddressedTo(wraps, bobPub),
      myPrivateKeyHex: eveKey,
      myPubkey: evePub,
    );

    expect(message, isNull);
  });

  test('a wrong key fails even when the address matches', () async {
    final wraps = await aliceWritesToBob('hi bob');

    final message = await unwrapPrivateMessage(
      giftWrap: wrapAddressedTo(wraps, bobPub),
      myPrivateKeyHex: eveKey,
      myPubkey: bobPub,
    );

    expect(message, isNull);
  });

  test('a modified gift wrap is rejected', () async {
    final wraps = await aliceWritesToBob('hi bob');
    final original = wrapAddressedTo(wraps, bobPub);

    final forged = NostrEvent(
      id: original.id,
      pubkey: original.pubkey,
      createdAt: original.createdAt,
      kind: original.kind,
      tags: original.tags,
      content: '${original.content}A',
      sig: original.sig,
    );

    final message = await unwrapPrivateMessage(
      giftWrap: forged,
      myPrivateKeyHex: bobKey,
      myPubkey: bobPub,
    );

    expect(message, isNull);
  });

  test('an author cannot be impersonated', () async {
    // Eve signs the seal, but the chat message claims that Alice wrote it.
    final claimedRumor = buildRumorJson(
      senderPubkey: alicePub,
      recipients: [bobPub],
      content: 'I am Alice',
      createdAt: now,
    );
    final forgedSeal = await buildSeal(
      senderPrivateKeyHex: eveKey,
      rumorJson: claimedRumor,
      recipientPubkey: bobPub,
      createdAt: now,
    );
    final forgedWrap = await buildGiftWrap(
      seal: forgedSeal,
      recipientPubkey: bobPub,
      createdAt: now,
    );

    final message = await unwrapPrivateMessage(
      giftWrap: forgedWrap,
      myPrivateKeyHex: bobKey,
      myPubkey: bobPub,
    );

    expect(message, isNull);
  });

  test('an edited chat message is rejected', () async {
    final rumor = buildRumorJson(
      senderPubkey: alicePub,
      recipients: [bobPub],
      content: 'original text',
      createdAt: now,
    );
    rumor['content'] = 'edited text';

    final seal = await buildSeal(
      senderPrivateKeyHex: aliceKey,
      rumorJson: rumor,
      recipientPubkey: bobPub,
      createdAt: now,
    );
    final wrap = await buildGiftWrap(
      seal: seal,
      recipientPubkey: bobPub,
      createdAt: now,
    );

    final message = await unwrapPrivateMessage(
      giftWrap: wrap,
      myPrivateKeyHex: bobKey,
      myPubkey: bobPub,
    );

    expect(message, isNull);
  });

  test('gift wrap timestamps are backdated, never in the future', () async {
    final wraps = await aliceWritesToBob('hi bob');

    for (final wrap in wraps) {
      expect(wrap.kind, kGiftWrapKind);
      expect(wrap.createdAt, lessThanOrEqualTo(now));
      expect(wrap.createdAt, greaterThanOrEqualTo(now - twoDays));
    }
  });

  test('empty, self-addressed and oversized messages are refused', () async {
    await expectLater(
      wrapPrivateMessage(
        senderPrivateKeyHex: aliceKey,
        senderPubkey: alicePub,
        recipients: [bobPub],
        content: '   ',
      ),
      throwsArgumentError,
    );
    await expectLater(
      wrapPrivateMessage(
        senderPrivateKeyHex: aliceKey,
        senderPubkey: alicePub,
        recipients: [alicePub],
        content: 'a note to myself',
      ),
      throwsArgumentError,
    );
    await expectLater(
      wrapPrivateMessage(
        senderPrivateKeyHex: aliceKey,
        senderPubkey: alicePub,
        recipients: [bobPub],
        content: 'x' * (maxPrivateMessageChars + 1),
      ),
      throwsArgumentError,
    );
  });
}
