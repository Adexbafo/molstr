import 'dart:convert';

import '../nostr/nostr_event.dart';

class ZapReceipt {
  const ZapReceipt({
    required this.amountMsats,
    required this.senderPubkey,
    required this.recipientPubkey,
    required this.comment,
    this.eventId,
  });

  final int amountMsats;
  final String senderPubkey;
  final String recipientPubkey;
  final String comment;
  final String? eventId;
}

/// Returns null unless the receipt embeds a validly signed kind-9734 request
/// whose amount and recipient agree with the receipt.
ZapReceipt? validateZapReceipt(NostrEvent receipt) {
  if (receipt.kind != 9735) return null;

  String? recipient;
  String? description;
  int? receiptAmount;

  for (final tag in receipt.tags) {
    if (tag.length < 2) continue;
    switch (tag[0]) {
      case 'p':
        recipient ??= tag[1].toLowerCase();
      case 'description':
        description ??= tag[1];
      case 'amount':
        receiptAmount ??= int.tryParse(tag[1]);
    }
  }

  if (recipient == null || description == null) return null;

  final Map<String, dynamic> requestJson;
  try {
    final decoded = jsonDecode(description);
    if (decoded is! Map<String, dynamic>) return null;
    requestJson = decoded;
  } catch (_) {
    return null;
  }

  final request = NostrEvent.fromJsonVerified(requestJson);
  if (request == null || request.kind != 9734) return null;

  int? requestAmount;
  String? requestRecipient;
  String? requestEventId;

  for (final tag in request.tags) {
    if (tag.length < 2) continue;
    switch (tag[0]) {
      case 'amount':
        requestAmount ??= int.tryParse(tag[1]);
      case 'p':
        requestRecipient ??= tag[1].toLowerCase();
      case 'e':
        requestEventId ??= tag[1].toLowerCase();
    }
  }

  if (requestAmount == null || requestAmount <= 0) return null;
  if (requestRecipient != recipient) return null;
  if (receiptAmount != null && receiptAmount != requestAmount) return null;

  return ZapReceipt(
    amountMsats: requestAmount,
    senderPubkey: request.pubkey,
    recipientPubkey: recipient,
    comment: request.content,
    eventId: requestEventId,
  );
}
