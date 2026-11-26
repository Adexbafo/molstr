// ignore_for_file: experimental_member_use
import 'dart:convert';

import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/nostr_event.dart';
import 'package:molstr/core/payments/nwc.dart';
import 'package:ndk/shared/nips/nip44/nip44.dart' as nip44;

void main() {
  // Disposable keys: the wallet service key simulates Rizful's side.
  final walletPriv = List.filled(32, 'aa').join();
  final walletPub = bip340.getPublicKey(walletPriv);
  final clientSecret = List.filled(32, 'bb').join();
  final clientPub = bip340.getPublicKey(clientSecret);

  NwcConnection makeConnection() => NwcConnection.parse(
        'nostr+walletconnect://$walletPub'
        '?relay=wss://relay.primal.net'
        '&relay=wss://relay.mostr.pub'
        '&secret=$clientSecret',
      );

  test('parses wallet pubkey, multiple relays, and secret', () {
    final connection = makeConnection();
    expect(connection.walletPubkey, walletPub);
    expect(
        connection.relays, ['wss://relay.primal.net', 'wss://relay.mostr.pub']);
    expect(connection.secret, clientSecret);
    expect(connection.clientPubkey, clientPub);
  });

  test('rejects bad scheme, secret, and relays', () {
    expect(
      () => NwcConnection.parse('https://example.com'),
      throwsFormatException,
    );
    expect(
      () => NwcConnection.parse(
        'nostr+walletconnect://$walletPub?relay=wss://r.example.com&secret=zz',
      ),
      throwsFormatException,
    );
    expect(
      () => NwcConnection.parse(
        'nostr+walletconnect://$walletPub?secret=$clientSecret',
      ),
      throwsFormatException,
    );
    expect(
      () => NwcConnection.parse(
        'nostr+walletconnect://$walletPub?relay=ws://r.example.com&secret=$clientSecret',
      ),
      throwsFormatException,
    );
  });

  test('request is kind 23194, addressed to the wallet, and decryptable',
      () async {
    final connection = makeConnection();
    final request = await buildNwcRequest(
      connection: connection,
      method: 'get_info',
      params: {},
      createdAt: 1700000000,
    );

    expect(request.kind, kNwcRequestKind);
    expect(request.pubkey, clientPub);
    expect(request.tags, contains(equals(['p', walletPub])));

    // The simulated wallet decrypts with its own private key.
    final plaintext = await nip44.Nip44.decryptMessage(
      request.content,
      walletPriv,
      clientPub,
    );
    final payload = jsonDecode(plaintext) as Map<String, dynamic>;
    expect(payload['method'], 'get_info');
  });

  test('parseNwcResponse accepts a matching encrypted response', () async {
    final connection = makeConnection();
    final request = await buildNwcRequest(
      connection: connection,
      method: 'pay_invoice',
      params: {'invoice': 'lnbc210n1test'},
      createdAt: 1700000000,
    );

    final responseJson = jsonEncode({
      'result_type': 'pay_invoice',
      'result': {'paid': true},
    });
    final responseContent = await nip44.Nip44.encryptMessage(
      responseJson,
      walletPriv,
      clientPub,
    );
    final response = NostrEvent.sign(
      privateKeyHex: walletPriv,
      kind: kNwcResponseKind,
      content: responseContent,
      tags: [
        ['p', clientPub],
        ['e', request.id],
      ],
      createdAt: 1700000001,
    );

    final parsed = await parseNwcResponse(
      response: response,
      request: request,
      connection: connection,
    );

    expect(parsed, isNotNull);
    expect(parsed!.success, isTrue);
    expect(parsed.resultType, 'pay_invoice');
    expect(parsed.result['paid'], isTrue);
  });

  test('rejects foreign senders and mismatched request ids', () async {
    final connection = makeConnection();
    final request = await buildNwcRequest(
      connection: connection,
      method: 'get_info',
      params: {},
      createdAt: 1700000000,
    );

    final strangerPriv = List.filled(32, 'cc').join();
    final content = await nip44.Nip44.encryptMessage(
      jsonEncode({'result_type': 'get_info', 'result': {}}),
      strangerPriv,
      clientPub,
    );
    final forged = NostrEvent.sign(
      privateKeyHex: strangerPriv,
      kind: kNwcResponseKind,
      content: content,
      tags: [
        ['p', clientPub],
        ['e', request.id],
      ],
      createdAt: 1700000001,
    );

    expect(
      await parseNwcResponse(
        response: forged,
        request: request,
        connection: connection,
      ),
      isNull,
    );
  });

  test('error responses carry code and message with success false', () async {
    final connection = makeConnection();
    final request = await buildNwcRequest(
      connection: connection,
      method: 'pay_invoice',
      params: {'invoice': 'bad'},
      createdAt: 1700000000,
    );

    final content = await nip44.Nip44.encryptMessage(
      jsonEncode({
        'result_type': 'pay_invoice',
        'error': {'code': 'INSUFFICIENT_BALANCE', 'message': 'not enough'},
      }),
      walletPriv,
      clientPub,
    );
    final response = NostrEvent.sign(
      privateKeyHex: walletPriv,
      kind: kNwcResponseKind,
      content: content,
      tags: [
        ['p', clientPub],
        ['e', request.id],
      ],
      createdAt: 1700000001,
    );

    final parsed = await parseNwcResponse(
      response: response,
      request: request,
      connection: connection,
    );

    expect(parsed!.success, isFalse);
    expect(parsed.errorCode, 'INSUFFICIENT_BALANCE');
  });
}
