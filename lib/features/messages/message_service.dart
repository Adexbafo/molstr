import 'package:flutter/foundation.dart';

import '../../core/nostr/identity_service.dart';
import '../../core/nostr/nip19.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/dm_relays.dart';
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

class SendResult {
  const SendResult({
    required this.recipientAccepted,
    required this.selfAccepted,
    required this.relaysTried,
  });

  /// How many relays accepted the copy addressed to the partner.
  final int recipientAccepted;

  /// How many relays accepted the copy addressed to us.
  final int selfAccepted;

  final int relaysTried;

  bool get deliveredToPartner => recipientAccepted > 0;
  bool get savedForSelf => selfAccepted > 0;
}

/// A decrypted conversation list.
///
/// The nsec is read from secure storage only inside [decryptMessages] and
/// [sendMessage]. Relay payloads and decrypted messages are kept separate:
/// relays never see plaintext.
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

    final ownDmRelays = await fetchDmRelayList(pubkey, relays);
    final queryRelays = <String>{...relays, ...ownDmRelays}.toList();

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

      final query = await relayService.queryEvents(filter, queryRelays);
      if (!query.reachedRelay) break;

      final events = query.events;
      if (events.isEmpty) break;

      allWraps.addAll(events);
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

    // Heavy crypto (two NIP-44 decryptions per wrap) runs off the UI thread.
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

  /// Fetches the newest verified kind 10050 DM relay list for [pubkey].
  /// Returns an empty list when none is published or no relay answers.
  Future<List<String>> fetchDmRelayList(
    String pubkey,
    List<String> relays,
  ) async {
    try {
      final query = await relayService.queryEvents(
        {
          'kinds': [kDmRelayListKind],
          'authors': [pubkey.toLowerCase()],
          'limit': 1,
        },
        relays,
      );
      if (!query.reachedRelay || query.events.isEmpty) return const [];

      final events = query.events.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return parseDmRelayList(events.first);
    } catch (_) {
      return const [];
    }
  }

  /// Signs and publishes our own kind 10050 DM relay list.
  /// Returns relay URL -> status (`ok`, `rejected: ...`, `timeout`, ...).
  Future<Map<String, String>> publishDmRelayList({
    required List<String> dmRelays,
    required List<String> publishRelays,
  }) async {
    final me = await identityService.currentIdentity();
    if (me == null) {
      throw StateError('Connect a key in Profile to publish a DM relay list.');
    }
    if (publishRelays.isEmpty) {
      throw StateError('No relays are configured.');
    }

    final cleaned = <String>[];
    final seen = <String>{};
    for (final raw in dmRelays) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.scheme.toLowerCase() != 'wss' ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw FormatException('Invalid DM relay (must be wss://...): $value');
      }
      if (seen.add(value)) cleaned.add(value);
    }
    if (cleaned.isEmpty) {
      throw const FormatException('Choose at least one DM relay.');
    }

    final event = await identityService.signEvent(
      kind: kDmRelayListKind,
      content: '',
      tags: [
        for (final relay in cleaned) ['relay', relay],
      ],
    );
    return relayService.publishEvent(event, publishRelays);
  }

  /// Wraps and publishes one message: a copy for [partnerPubkey] and a copy
  /// for the sender, so the message appears in both inboxes.
  ///
  /// The partner's copy goes to the partner's kind-10050 DM relay list when
  /// they have one, otherwise to [relays]. The sender's copy always goes to
  /// [relays] — publishing our own DM relay list is a separate slice.
  Future<SendResult> sendMessage({
    required String senderPubkey,
    required String partnerPubkey,
    required String content,
    required List<String> relays,
  }) async {
    if (relays.isEmpty) {
      throw StateError('No relays are configured.');
    }

    final senderPrivateKey = await identityService.currentNsecHex();
    if (senderPrivateKey == null) {
      throw StateError('Connect a key in Profile to send messages.');
    }

    final wraps = await wrapPrivateMessage(
      senderPrivateKeyHex: senderPrivateKey,
      senderPubkey: senderPubkey,
      recipients: [partnerPubkey],
      content: content,
    );

    final me = senderPubkey.toLowerCase();
    final partner = partnerPubkey.toLowerCase();

    final partnerDmRelays = await _fetchDmRelaysFor(
      pubkey: partner,
      fallbackRelays: relays,
    );
    final ownDmRelays = await _fetchDmRelaysFor(
      pubkey: me,
      fallbackRelays: relays,
    );

    var recipientAccepted = 0;
    var selfAccepted = 0;

    for (final wrap in wraps) {
      final addressedTo = _addressedPubkey(wrap);
      final targets = addressedTo == partner ? partnerDmRelays : ownDmRelays;

      final result = await relayService.publishEvent(wrap, targets);
      final accepted = result.values.where((value) => value == 'ok').length;

      if (addressedTo == partner) {
        recipientAccepted = accepted;
      } else if (addressedTo == me) {
        selfAccepted = accepted;
      }
    }

    return SendResult(
      recipientAccepted: recipientAccepted,
      selfAccepted: selfAccepted,
      relaysTried: partnerDmRelays.length,
    );
  }

  Future<List<String>> _fetchDmRelaysFor({
    required String pubkey,
    required List<String> fallbackRelays,
  }) async {
    try {
      final query = await relayService.queryEvents(
        {
          'kinds': [kDmRelayListKind],
          'authors': [pubkey],
          'limit': 1,
        },
        fallbackRelays,
      );
      if (!query.reachedRelay || query.events.isEmpty) {
        return fallbackRelays;
      }

      final events = query.events.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final parsed = parseDmRelayList(events.first);
      return parsed.isEmpty ? fallbackRelays : parsed;
    } catch (_) {
      return fallbackRelays;
    }
  }

  String? _addressedPubkey(NostrEvent wrap) {
    for (final tag in wrap.tags) {
      if (tag.length >= 2 && tag[0] == 'p') {
        return tag[1].toLowerCase();
      }
    }
    return null;
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
  final npub = Nip19.npubFromHex(pubkeyHex.toLowerCase());
  return '${npub.substring(0, 12)}…${npub.substring(npub.length - 6)}';
}
