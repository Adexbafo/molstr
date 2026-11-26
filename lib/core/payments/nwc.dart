import 'dart:async';
import 'dart:convert';

import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter/foundation.dart';

import '../nostr/nostr_event.dart';
import '../nostr/relay_service.dart';
import 'nwc_cipher.dart';

const int kNwcRequestKind = 23194;
const int kNwcResponseKind = 23195;
const int kNwcInfoKind = 13194;

class NwcConnection {
  const NwcConnection({
    required this.walletPubkey,
    required this.relays,
    required this.secret,
  });

  final String walletPubkey;
  final List<String> relays;
  final String secret;

  String get clientPubkey => bip340.getPublicKey(secret);

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

Future<NostrEvent> buildNwcRequest({
  required NwcConnection connection,
  required String method,
  required Map<String, dynamic> params,
  NwcEncryption encryption = NwcEncryption.nip44V2,
  int? createdAt,
}) async {
  final payload = jsonEncode({'method': method, 'params': params});
  final content = await encryptNwcContent(
    plaintext: payload,
    secret: connection.secret,
    peerPubkey: connection.walletPubkey,
    mode: encryption,
  );
  return NostrEvent.sign(
    privateKeyHex: connection.secret,
    kind: kNwcRequestKind,
    content: content,
    tags: [
      ['p', connection.walletPubkey],
      if (encryption == NwcEncryption.nip44V2) ['encryption', 'nip44_v2'],
    ],
    createdAt: createdAt,
  );
}

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
    final matches = response.tags.where((tag) =>
        tag.length >= 2 &&
        tag[0] == 'e' &&
        tag[1].toLowerCase() == request.id.toLowerCase());
    if (matches.isEmpty) return null;

    final plaintext = await decryptNwcContent(
      payload: response.content,
      secret: connection.secret,
      peerPubkey: response.pubkey,
    );
    if (plaintext == null) return null;

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

Future<NwcResponse?> sendNwcRequest({
  required NwcConnection connection,
  required RelayService relayService,
  required String method,
  Map<String, dynamic> params = const {},
  NwcEncryption encryption = NwcEncryption.nip44V2,
  Duration overallTimeout = const Duration(seconds: 30),
}) async {
  final request = await buildNwcRequest(
    connection: connection,
    method: method,
    params: params,
    encryption: encryption,
  );
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

Future<NwcResponse?> walletGetInfo({
  required NwcConnection connection,
  required RelayService relayService,
  NwcEncryption encryption = NwcEncryption.nip44V2,
}) {
  return sendNwcRequest(
    connection: connection,
    relayService: relayService,
    method: 'get_info',
    encryption: encryption,
  );
}

Future<NwcResponse?> walletGetBalance({
  required NwcConnection connection,
  required RelayService relayService,
  NwcEncryption encryption = NwcEncryption.nip44V2,
}) {
  return sendNwcRequest(
    connection: connection,
    relayService: relayService,
    method: 'get_balance',
    encryption: encryption,
  );
}

Future<NwcResponse?> walletPayInvoice({
  required NwcConnection connection,
  required RelayService relayService,
  required String invoice,
  NwcEncryption encryption = NwcEncryption.nip44V2,
}) {
  return sendNwcRequest(
    connection: connection,
    relayService: relayService,
    method: 'pay_invoice',
    params: {'invoice': invoice},
    encryption: encryption,
    overallTimeout: const Duration(seconds: 45),
  );
}
