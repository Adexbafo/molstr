// ignore_for_file: experimental_member_use
//
// NIP-17 private direct messages: NIP-44 encryption plus NIP-59 seal and
// gift wrap. This file does no networking and no storage. Every function
// takes its keys as arguments, so it can be tested with disposable keys.
//
// NIP-44 comes from the ndk package. ndk marks that class experimental, so
// the analyzer warning is silenced for this file only.
// The seal and gift-wrap layers are built on MolStr's NostrEvent code.

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:ndk/shared/nips/nip44/nip44.dart' as nip44;

import 'nip19.dart';
import 'nostr_event.dart';

/// NIP-17 chat message. It travels unsigned inside a seal.
const int kChatMessageKind = 14;

/// NIP-59 seal. Signed by the real author and encrypted to one recipient.
const int kSealKind = 13;

/// NIP-59 gift wrap. Signed by a throwaway key and addressed with a p tag.
const int kGiftWrapKind = 1059;

/// Longest message we will send, in characters.
const int maxPrivateMessageChars = 4000;

/// NIP-59 allows seal and wrap timestamps to be backdated up to two days.
const int _maxBackdateSeconds = 2 * 24 * 60 * 60;

final Random _random = Random.secure();

/// One message, after both layers were opened and checked.
class PrivateMessage {
  const PrivateMessage({
    required this.id,
    required this.senderPubkey,
    required this.recipients,
    required this.content,
    required this.createdAt,
    required this.giftWrapId,
  });

  /// Id of the unsigned chat message. The same for every copy.
  final String id;

  /// Lowercase hex pubkey of the real author.
  final String senderPubkey;

  /// Lowercase hex pubkeys from the chat message's p tags.
  final List<String> recipients;

  final String content;
  final int createdAt;

  /// Id of the gift wrap this copy arrived in. Used to drop duplicates.
  final String giftWrapId;

  /// The other person in a one-to-one chat, seen from [myPubkey].
  String? partnerFor(String myPubkey) {
    if (senderPubkey == myPubkey.toLowerCase()) {
      return recipients.isEmpty ? null : recipients.first;
    }
    return senderPubkey;
  }
}

/// Returns the lowercase hex pubkey, or throws [FormatException].
String normalizePubkey(String key) {
  final value = key.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw const FormatException('Invalid public key.');
  }
  return value;
}

/// The unsigned chat message (kind 14) as a JSON-ready map.
///
/// Its id is computed the same way as a normal event id, but it has no
/// signature. Its author is trusted only when it matches the seal's signer,
/// which unwrapPrivateMessage checks.
Map<String, dynamic> buildRumorJson({
  required String senderPubkey,
  required List<String> recipients,
  required String content,
  required int createdAt,
  String? replyToId,
}) {
  final sender = normalizePubkey(senderPubkey);
  final tags = <List<String>>[
    for (final recipient in recipients) ['p', normalizePubkey(recipient)],
    if (replyToId != null) ['e', replyToId, '', 'reply'],
  ];
  final id = NostrEvent.computeId(
    pubkey: sender,
    createdAt: createdAt,
    kind: kChatMessageKind,
    tags: tags,
    content: content,
  );

  return {
    'id': id,
    'pubkey': sender,
    'created_at': createdAt,
    'kind': kChatMessageKind,
    'tags': tags,
    'content': content,
  };
}

/// Seal (kind 13): the rumor, encrypted from the sender to [recipientPubkey]
/// and then signed by the sender. NIP-59 requires empty tags.
Future<NostrEvent> buildSeal({
  required String senderPrivateKeyHex,
  required Map<String, dynamic> rumorJson,
  required String recipientPubkey,
  required int createdAt,
}) async {
  final ciphertext = await nip44.Nip44.encryptMessage(
    jsonEncode(rumorJson),
    senderPrivateKeyHex,
    normalizePubkey(recipientPubkey),
  );

  return NostrEvent.sign(
    privateKeyHex: senderPrivateKeyHex,
    kind: kSealKind,
    content: ciphertext,
    createdAt: createdAt,
  );
}

/// Gift wrap (kind 1059): the whole seal, encrypted from a new throwaway key
/// to [recipientPubkey] and signed by that throwaway key.
Future<NostrEvent> buildGiftWrap({
  required NostrEvent seal,
  required String recipientPubkey,
  required int createdAt,
}) async {
  final recipient = normalizePubkey(recipientPubkey);
  final throwawayPrivateKeyHex = _randomPrivateKeyHex();

  final ciphertext = await nip44.Nip44.encryptMessage(
    jsonEncode(seal.toJson()),
    throwawayPrivateKeyHex,
    recipient,
  );

  return NostrEvent.sign(
    privateKeyHex: throwawayPrivateKeyHex,
    kind: kGiftWrapKind,
    content: ciphertext,
    tags: [
      ['p', recipient],
    ],
    createdAt: createdAt,
  );
}

/// Builds the gift wraps for one message: one for each recipient, plus one
/// for the sender, so the message also appears in the sender's own inbox.
///
/// Each copy gets its own seal, because a seal is encrypted to one recipient.
Future<List<NostrEvent>> wrapPrivateMessage({
  required String senderPrivateKeyHex,
  required String senderPubkey,
  required List<String> recipients,
  required String content,
  String? replyToId,
  int? nowSeconds,
}) async {
  final sender = normalizePubkey(senderPubkey);
  final others = <String>{
    for (final recipient in recipients) normalizePubkey(recipient),
  }..remove(sender);

  if (others.isEmpty) {
    throw ArgumentError('Choose a recipient other than yourself.');
  }

  final text = content.trim();
  if (text.isEmpty) {
    throw ArgumentError('The message is empty.');
  }
  if (text.length > maxPrivateMessageChars) {
    throw ArgumentError(
      'Messages can be at most $maxPrivateMessageChars characters.',
    );
  }

  final now = nowSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final rumor = buildRumorJson(
    senderPubkey: sender,
    recipients: others.toList(),
    content: text,
    createdAt: now,
    replyToId: replyToId,
  );

  final wraps = <NostrEvent>[];
  for (final target in {...others, sender}) {
    final seal = await buildSeal(
      senderPrivateKeyHex: senderPrivateKeyHex,
      rumorJson: rumor,
      recipientPubkey: target,
      createdAt: _backdated(now),
    );
    wraps.add(
      await buildGiftWrap(
        seal: seal,
        recipientPubkey: target,
        createdAt: _backdated(now),
      ),
    );
  }
  return wraps;
}

/// Opens a gift wrap that should be addressed to [myPubkey].
///
/// Returns null for anything that is not a valid message to us: the wrong
/// key, altered data, a forged author, or a malformed payload. It never throws.
Future<PrivateMessage?> unwrapPrivateMessage({
  required NostrEvent giftWrap,
  required String myPrivateKeyHex,
  required String myPubkey,
}) async {
  try {
    final me = normalizePubkey(myPubkey);
    if (giftWrap.kind != kGiftWrapKind || !giftWrap.verify()) return null;

    final addressedToMe = giftWrap.tags.any(
      (tag) => tag.length >= 2 && tag[0] == 'p' && tag[1].toLowerCase() == me,
    );
    if (!addressedToMe) return null;

    // Outer layer: throwaway key to me.
    final sealJson = await nip44.Nip44.decryptMessage(
      giftWrap.content,
      myPrivateKeyHex,
      giftWrap.pubkey,
    );
    final seal = NostrEvent.fromJsonVerified(
      jsonDecode(sealJson) as Map<String, dynamic>,
    );
    if (seal == null || seal.kind != kSealKind || seal.tags.isNotEmpty) {
      return null;
    }

    // Inner layer: real author to me.
    final rumorText = await nip44.Nip44.decryptMessage(
      seal.content,
      myPrivateKeyHex,
      seal.pubkey,
    );
    final rumor = jsonDecode(rumorText);
    if (rumor is! Map<String, dynamic>) return null;

    final rumorId = rumor['id'];
    final rumorPubkey = rumor['pubkey'];
    final rumorCreatedAt = rumor['created_at'];
    final rumorKind = rumor['kind'];
    final rumorContent = rumor['content'];
    final rumorTags = _parseTags(rumor['tags']);

    if (rumorId is! String ||
        rumorPubkey is! String ||
        rumorCreatedAt is! int ||
        rumorKind != kChatMessageKind ||
        rumorContent is! String ||
        rumorTags == null) {
      return null;
    }

    // The seal's signer must be the author the message names. Without this
    // check, anyone could send a message that claims to come from someone else.
    final author = rumorPubkey.toLowerCase();
    if (author != seal.pubkey.toLowerCase()) return null;

    // The id must match the contents, so nothing changed after it was made.
    final expectedId = NostrEvent.computeId(
      pubkey: author,
      createdAt: rumorCreatedAt,
      kind: kChatMessageKind,
      tags: rumorTags,
      content: rumorContent,
    );
    if (expectedId != rumorId) return null;

    return PrivateMessage(
      id: rumorId,
      senderPubkey: author,
      recipients: [
        for (final tag in rumorTags)
          if (tag.length >= 2 && tag[0] == 'p') tag[1].toLowerCase(),
      ],
      content: rumorContent,
      createdAt: rumorCreatedAt,
      giftWrapId: giftWrap.id,
    );
  } catch (error) {
    debugPrint('MolStr: could not open private message ${giftWrap.id}: $error');
    return null;
  }
}

List<List<String>>? _parseTags(Object? raw) {
  if (raw is! List) return null;
  final tags = <List<String>>[];
  for (final tag in raw) {
    if (tag is! List) return null;
    final items = <String>[];
    for (final item in tag) {
      if (item is! String) return null;
      items.add(item);
    }
    tags.add(items);
  }
  return tags;
}

String _randomPrivateKeyHex() {
  final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
  return Nip19.bytesToHex(bytes);
}

int _backdated(int now) => now - _random.nextInt(_maxBackdateSeconds);
