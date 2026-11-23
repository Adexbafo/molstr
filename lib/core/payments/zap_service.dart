import 'dart:convert';

import 'package:http/http.dart' as http;

import '../nostr/nostr_event.dart';
import 'lnurl.dart';

List<List<String>> buildZapRequestTags({
  required String recipientPubkeyHex,
  required int amountMsats,
  required List<String> relays,
  String? eventId,
}) {
  final pubkey = recipientPubkeyHex.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(pubkey)) {
    throw const FormatException('Invalid recipient key.');
  }
  if (amountMsats <= 0) {
    throw const FormatException('Amount must be greater than zero.');
  }
  String? normalizedEventId;
  if (eventId != null) {
    final e = eventId.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(e)) {
      throw const FormatException('Invalid event id.');
    }
    normalizedEventId = e;
  }
  final cleanRelays =
      relays.map((r) => r.trim()).where((r) => r.isNotEmpty).take(5).toList();
  return [
    ['p', pubkey],
    if (cleanRelays.isNotEmpty) ['relays', ...cleanRelays],
    ['amount', amountMsats.toString()],
    if (normalizedEventId != null) ['e', normalizedEventId],
  ];
}

Future<String> fetchZapInvoice({
  required LnurlPayParams params,
  required NostrEvent zapRequest,
  required int amountMsats,
}) async {
  validateAmountMsats(amountMsats, params);
  if (zapRequest.kind != 9734) {
    throw const FormatException('Invalid zap request.');
  }
  final callbackUri = Uri.parse(params.callback);
  final requestUri = callbackUri.replace(queryParameters: {
    ...callbackUri.queryParameters,
    'amount': amountMsats.toString(),
    'nostr': jsonEncode(zapRequest.toJson()),
  });
  final res = await http.get(requestUri).timeout(const Duration(seconds: 12));
  if (res.statusCode != 200) {
    throw Exception('Invoice request failed (${res.statusCode}).');
  }
  try {
    final data = jsonDecode(res.body);
    final pr = data is Map ? data['pr'] : null;
    if (pr is! String || pr.isEmpty) {
      throw const FormatException('LNURL server did not return an invoice.');
    }
    final lower = pr.toLowerCase();
    if (!lower.startsWith('lnbc') &&
        !lower.startsWith('lntb') &&
        !lower.startsWith('lnbcrt')) {
      throw const FormatException('LNURL server returned an invalid invoice.');
    }
    return pr;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Invalid invoice response.');
  }
}
