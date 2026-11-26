import 'dart:async';
// ignore_for_file: experimental_member_use
import 'dart:convert';

import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter/foundation.dart';
import 'package:ndk/shared/nips/nip44/nip44.dart' as nip44;

import '../nostr/nostr_event.dart';
import '../nostr/relay_service.dart';

/// NIP-47 (Nostr Wallet Connect) event kinds.
const int kNwcRequestKind = 23194;
const int kNwcResponseKind = 23195;
const int kNwcInfoKind = 13194;

/// A parsed NWC connection URI of the form:
/// `nostr+walletconnect://PUBKEY?relay=wss://...&secret=HEX`
///
/// The URI secret is also the client's private key per NIP-47, so requests
/// are signed with it. It must never be logged, stored in preferences, or
/// committed. The caller keeps it in secure storage.
class NwcConnection {
  const NwcConnection({
    required this.walletPubkey,
    required this.relays,
    required this.secret,
  });

  final String walletPubkey;
  final List<String> relays;
  final String secret;

  /// Derived client pubkey (requests are signed with the secret).
  String get clientPubkey => bip340.getPublicKey(secret);

  /// Parses without keeping any copy of [uri] in logs.
  static NwcConnection parse(String uri) {
    final parsed = Uri.tryParse(uri.trim());
    if (parsed == null ||
        parsed.scheme.toLowerCase() != 'nostr+walletconnect') {
      throw const FormatException(
        'Connection strings start with nostr+walletconnect://',
      );
    }

    final wallet = parsed.host.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(wallet)) {
      throw const FormatException('Invalid wallet service public key.');
    }

    final secrets = parsed.queryParametersAll['secret'] ?? const [];
    if (secrets.length != 1 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(secrets.first)) {
      throw const FormatException(
        'Connection string must contain one 64-character hex secret.',
      );
    }

    final relays = <String>[];
    for (final relay in parsed.queryParametersAll['relay'] ?? const []) {
      final relayUri = Uri.tryParse(relay.trim());
      if (relayUri == null ||
          relayUri.scheme.toLowerCase() != 'wss' ||
          relayUri.host.isEmpty ||
          relayUri.userInfo.isNotEmpty) {
        throw FormatException('Invalid relay in connection string: $relay');
      }
      relays.add(relay.trim());
    }
    if (relays.isEmpty) {
      throw const FormatException(
        'Connection string must contain at least one relay.',
      );
    }

    return NwcConnection(
      walletPubkey: wallet,
      relays: relays,
      secret: secrets.first,
    );
  }
}

class NwcResponse {
  const NwcResponse({
    required this.requestId,
    required this.success,
    required this.resultType,
    this.result = const {},
    this.errorCode,
    this.errorMessage,
  });

  final String requestId;
  final bool success;
  final String resultType;
  final Map<String, dynamic> result;
  final String? errorCode;
  final String? errorMessage;
}

/// Builds a signed, NIP-44-encrypted kind 23194 request.
/// [connection.secret] is used only inside this call.
Future<NostrEvent> buildNwcRequest({
  required NwcConnection connection,
  required String method,
  required Map<String, dynamic> params,
  int? createdAt,
}) async {
  final payload = jsonEncode({
    'method': method,
    'params': params,
  });
  final content = await nip44.Nip44.encryptMessage(
    payload,
    connection.secret,
    connection.walletPubkey,
  );

  return NostrEvent.sign(
    privateKeyHex: connection.secret,
    kind: kNwcRequestKind,
    content: content,
    tags: [
      ['p', connection.walletPubkey],
    ],
    createdAt: createdAt,
  );
}

/// Decrypts and validates a kind 23195 response for [request].
/// Returns null for responses from the wrong wallet, about another request,
/// or that fail authentication — those are not our data.
Future<NwcResponse?> parseNwcResponse({
  required NostrEvent response,
  required NostrEvent request,
  required NwcConnection connection,
}) async {
  try {
    if (response.kind != kNwcResponseKind) return null;

    final fromWallet =
        response.pubkey.toLowerCase() == connection.walletPubkey.toLowerCase();
    if (!fromWallet) return null;

    final addressedToMe = response.tags.any(
      (tag) =>
          tag.length >= 2 &&
          tag[0] == 'p' &&
          tag[1].toLowerCase() == connection.clientPubkey,
    );
    if (!addressedToMe) return null;

    final requestId = response.tags
        .where((tag) => tag.length >= 2 && tag[0] == 'e')
        .map((tag) => tag[1].toLowerCase())
        .where((id) => id == request.id.toLowerCase());
    if (requestId.isEmpty) return null;

    final plaintext = await nip44.Nip44.decryptMessage(
      response.content,
      connection.secret,
      response.pubkey,
    );
    final decoded = jsonDecode(plaintext);
    if (decoded is! Map<String, dynamic>) return null;

    final resultType = decoded['result_type'];
    if (resultType is! String) return null;

    final error = decoded['error'];
    final result = decoded['result'];

    String? errorCode;
    String? errorMessage;
    if (error is Map<String, dynamic>) {
      errorCode = error['code'] is String ? error['code'] : null;
      errorMessage = error['message'] is String ? error['message'] : null;
    }

    return NwcResponse(
      requestId: request.id,
      success: error == null && result is Map<String, dynamic>,
      resultType: resultType,
      result: result is Map<String, dynamic> ? result : const {},
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  } catch (e) {
    debugPrint('MolStr: could not parse NWC response: $e');
    return null;
  }
}

/// Fetches the wallet service's public kind 13194 info event.
/// Returns null if no relay answers. The content is plain text describing
/// the service; NIP-47 does not standardise its format.
Future<String?> fetchWalletInfo({
  required NwcConnection connection,
  required RelayService relayService,
}) async {
  final query = await relayService.queryEvents(
    {
      'kinds': [kNwcInfoKind],
      'authors': [connection.walletPubkey],
      'limit': 1,
    },
    connection.relays,
  );
  if (!query.reachedRelay || query.events.isEmpty) return null;
  query.events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return query.events.first.content;
}

/// Sends [method] and waits for the matching encrypted response.
///
/// Polls rather than holding a live subscription, so it reuses the existing
/// verified relay plumbing. Returns null on timeout.
Future<NwcResponse?> sendNwcRequest({
  required NwcConnection connection,
  required RelayService relayService,
  required String method,
  Map<String, dynamic> params = const {},
  Duration overallTimeout = const Duration(seconds: 30),
}) async {
  final request = await buildNwcRequest(
    connection: connection,
    method: method,
    params: params,
  );

  // Publish once to every relay in the connection string.
  final publishResults =
      await relayService.publishEvent(request, connection.relays);
  final accepted = publishResults.values.where((value) => value == 'ok').length;
  if (accepted == 0) {
    throw Exception('No relay accepted the wallet request.');
  }

  final deadline = DateTime.now().add(overallTimeout);
  final since = request.createdAt - 5;

  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(seconds: 2));

    final query = await relayService.queryEvents(
      {
        'kinds': [kNwcResponseKind],
        '#p': [connection.clientPubkey],
        'since': since,
        'limit': 20,
      },
      connection.relays,
    );

    for (final event in query.events) {
      final response = await parseNwcResponse(
        response: event,
        request: request,
        connection: connection,
      );
      if (response != null) return response;
    }
  }

  return null;
}

/// Convenience wrapper: wallet get_info.
Future<NwcResponse?> walletGetInfo({
  required NwcConnection connection,
  required RelayService relayService,
}) {
  return sendNwcRequest(
    connection: connection,
    relayService: relayService,
    method: 'get_info',
  );
}

/// Convenience wrapper: pay a BOLT11 invoice. Returns the response, whose
/// success flag reflects the wallet's own answer.
Future<NwcResponse?> walletPayInvoice({
  required NwcConnection connection,
  required RelayService relayService,
  required String invoice,
}) {
  return sendNwcRequest(
    connection: connection,
    relayService: relayService,
    method: 'pay_invoice',
    params: {'invoice': invoice},
    overallTimeout: const Duration(seconds: 45),
  );
}
