import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/nostr_event.dart';
import 'package:molstr/core/payments/zap_receipt.dart';

void main() {
  final senderKey = List.filled(32, 'a1').join();
  final nodeKey = List.filled(32, 'b2').join();
  final noteId = List.filled(32, 'c3').join();

  NostrEvent request({int amount = 21000, String? recipient}) {
    final target = NostrEvent.sign(
      privateKeyHex: nodeKey,
      kind: 1,
      content: 'note',
      createdAt: 1700000000,
    );
    return NostrEvent.sign(
      privateKeyHex: senderKey,
      kind: 9734,
      content: 'gm',
      createdAt: 1700000001,
      tags: [
        ['p', recipient ?? target.pubkey],
        ['e', noteId],
        ['amount', '$amount'],
      ],
    );
  }

  NostrEvent receipt({
    required String description,
    required String recipient,
    List<List<String>> extra = const [],
  }) {
    return NostrEvent.sign(
      privateKeyHex: nodeKey,
      kind: 9735,
      content: '',
      createdAt: 1700000002,
      tags: [
        ['p', recipient],
        ['e', noteId],
        ['description', description],
        ...extra,
      ],
    );
  }

  test('accepts a receipt with a validly signed embedded request', () {
    final zap = request();
    final recipient = zap.tags.firstWhere((t) => t[0] == 'p')[1];
    final parsed = validateZapReceipt(
      receipt(
        description: jsonEncode(zap.toJson()),
        recipient: recipient,
      ),
    );

    expect(parsed, isNotNull);
    expect(parsed!.amountMsats, 21000);
    expect(parsed.eventId, noteId);
    expect(parsed.senderPubkey, zap.pubkey);
  });

  test('rejects a tampered embedded request', () {
    final zap = request();
    final json = zap.toJson();
    final tags = List<List<String>>.from(
      (json['tags'] as List).map((t) => List<String>.from(t as List)),
    );
    tags.firstWhere((t) => t[0] == 'amount')[1] = '999000000';
    json['tags'] = tags;

    final recipient = zap.tags.firstWhere((t) => t[0] == 'p')[1];
    expect(
      validateZapReceipt(
        receipt(description: jsonEncode(json), recipient: recipient),
      ),
      isNull,
    );
  });

  test('rejects recipient mismatch and missing description', () {
    final zap = request();
    final payload = jsonEncode(zap.toJson());
    final recipient = zap.tags.firstWhere((t) => t[0] == 'p')[1];

    expect(
      validateZapReceipt(
        receipt(description: payload, recipient: List.filled(64, 'f').join()),
      ),
      isNull,
    );
    expect(
      validateZapReceipt(
        NostrEvent.sign(
          privateKeyHex: nodeKey,
          kind: 9735,
          content: '',
          createdAt: 1700000003,
          tags: [
            ['p', recipient],
            ['amount', '999000000'],
          ],
        ),
      ),
      isNull,
    );
  });
}
