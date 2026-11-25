import 'package:flutter/foundation.dart';

import '../../core/nostr/identity_service.dart';
import '../../core/nostr/nip19.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/private_messages.dart';
import '../../core/nostr/relay_service.dart';

class Conversation {
  const Conversation({
    required this.partnerPubkey,
    required this.lastMessage,
    required this.messageCount,
  });

  final String partnerPubkey;
  final PrivateMessage lastMessage;
  final int messageCount;
}

/// A decrypted conversation list.
///
/// The nsec is read from secure storage only inside [decryptMessages].
/// Relay payloads and decrypted messages are kept separate: relays never see
/// plaintext, and the nsec never leaves the identity service.
class MessageService {
  MessageService({
    required this.identityService,
    required this.relayService,
    this.maxPages = 3,
    this.pageSize = 100,
  });

  final IdentityService identityService;
  final RelayService relayService;
  final int maxPages;
  final int pageSize;

  /// Fetch + decrypt gift wraps addressed to [pubkey], most recent first.
  Future<List<PrivateMessage>> loadMessages({
    required String pubkey,
    required List<String> relays,
    void Function(String status)? onStatus,
  }) async {
    if (pubkey.isEmpty || relays.isEmpty) return const [];

    final allWraps = <NostrEvent>[];
    var until = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 1;

    for (var page = 0; page < maxPages; page++) {
      onStatus?.call('Loading messages (page ${page + 1})…');

      final filter = <String, dynamic>{
        'kinds': [kGiftWrapKind],
        '#p': [pubkey.toLowerCase()],
        'limit': pageSize,
        'until': until,
      };

      final query = await relayService.queryEvents(filter, relays);
      if (!query.reachedRelay) break;

      final events = query.events;
      if (events.isEmpty) break;

      allWraps.addAll(events);

      // Stop if a relay returned fewer than a full page — no older pages exist.
      if (events.length < pageSize) break;

      events.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      until = events.first.createdAt - 1;
      if (until <= 0) break;
    }

    onStatus?.call('Decrypting ${allWraps.length} gift wraps…');
    return decryptMessages(allWraps);
  }

  /// Decrypts wraps that can be opened with the current key; others are
  /// skipped silently (e.g. messages addressed to a different account).
  Future<List<PrivateMessage>> decryptMessages(
    List<NostrEvent> wraps,
  ) async {
    if (wraps.isEmpty) return const [];

    final myPrivateKey = await identityService.currentNsecHex();
    final myPubkey = await identityService.currentPublicKeyHex();
    if (myPrivateKey == null || myPubkey == null) return const [];

    // Heavy crypto (2 NIP-44 decryptions per wrap) runs off the UI thread.
    final messages = await compute(
      _decryptBatch,
      _DecryptBatch(
        wrapsJson: wraps.map((w) => w.toJson()).toList(),
        myPrivateKeyHex: myPrivateKey,
        myPubkey: myPubkey,
      ),
    );

    // De-duplicate by rumor id (same content, different wrap id).
    final byRumor = <String, PrivateMessage>{};
    for (final message in messages) {
      final existing = byRumor[message.id];
      if (existing == null || message.createdAt > existing.createdAt) {
        byRumor[message.id] = message;
      }
    }

    final list = byRumor.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Groups [messages] into conversations keyed by the other party's pubkey.
  List<Conversation> conversationsFor(
    List<PrivateMessage> messages,
    String myPubkeyHex,
  ) {
    final me = myPubkeyHex.toLowerCase();
    final byPartner = <String, List<PrivateMessage>>{};

    for (final message in messages) {
      final partner = message.partnerFor(me);
      if (partner == null) continue;
      byPartner.putIfAbsent(partner, () => []).add(message);
    }

    final conversations = <Conversation>[];
    for (final entry in byPartner.entries) {
      final sorted = entry.value
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      conversations.add(
        Conversation(
          partnerPubkey: entry.key,
          lastMessage: sorted.first,
          messageCount: sorted.length,
        ),
      );
    }

    conversations.sort(
      (a, b) => b.lastMessage.createdAt.compareTo(a.lastMessage.createdAt),
    );
    return conversations;
  }
}

class _DecryptBatch {
  const _DecryptBatch({
    required this.wrapsJson,
    required this.myPrivateKeyHex,
    required this.myPubkey,
  });

  final List<Map<String, dynamic>> wrapsJson;
  final String myPrivateKeyHex;
  final String myPubkey;
}

/// Top-level function for `compute` — decrypts in a background isolate.
Future<List<PrivateMessage>> _decryptBatch(_DecryptBatch batch) async {
  final messages = <PrivateMessage>[];
  for (final json in batch.wrapsJson) {
    final event = NostrEvent.fromJsonVerified(json);
    if (event == null) continue;
    final message = await unwrapPrivateMessage(
      giftWrap: event,
      myPrivateKeyHex: batch.myPrivateKeyHex,
      myPubkey: batch.myPubkey,
    );
    if (message != null) messages.add(message);
  }
  return messages;
}

/// Convenience for labels: "npub1xyz…abc".
String shortNpubLabel(String pubkeyHex) {
  final npub = Nip19.npubFromHex(pubkeyHex);
  return '${npub.substring(0, 12)}…${npub.substring(npub.length - 6)}';
}
