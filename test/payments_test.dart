import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/payments/lnurl.dart';
import 'package:molstr/core/payments/monero.dart';
import 'package:molstr/core/payments/zap_service.dart';

void main() {
  group('LightningAddress', () {
    test('parses name and lowercases domain', () {
      final addr = LightningAddress.parse('MolStr@Rizful.com');
      expect(addr.name, 'MolStr');
      expect(addr.domain, 'rizful.com');
      expect(
        addr.lnurlpUrl.toString(),
        'https://rizful.com/.well-known/lnurlp/MolStr',
      );
    });

    test('rejects invalid addresses', () {
      expect(() => LightningAddress.parse('no-at-sign'), throwsFormatException);
      expect(() => LightningAddress.parse('a@b'), throwsFormatException);
      expect(() => LightningAddress.parse('a @b.com'), throwsFormatException);
    });
  });

  group('LnurlPayParams', () {
    test('parses a Nostr-capable response', () {
      final params = LnurlPayParams.fromJson({
        'callback': 'https://example.com/cb',
        'minSendable': 1000,
        'maxSendable': 11000000,
        'metadata': '[]',
        'allowsNostr': true,
        'nostrPubkey': List.filled(32, 'ab').join(),
      });
      expect(params.allowsNostr, isTrue);
      expect(params.minSendable, 1000);
    });

    test('rejects non-https callback', () {
      expect(
        () => LnurlPayParams.fromJson({
          'callback': 'http://example.com/cb',
          'minSendable': 1000,
          'maxSendable': 2000,
          'metadata': '[]',
        }),
        throwsFormatException,
      );
    });
  });

  group('amounts', () {
    test('sats convert to msats and validate against limits', () {
      expect(satsToMsats(21), 21000);
      final params = LnurlPayParams.fromJson({
        'callback': 'https://example.com/cb',
        'minSendable': 1000,
        'maxSendable': 11000000,
        'metadata': '[]',
      });
      validateAmountMsats(100000, params);
      expect(() => validateAmountMsats(1, params), throwsFormatException);
      expect(
        () => validateAmountMsats(999999999, params),
        throwsFormatException,
      );
    });
  });

  group('zap tags', () {
    test('include p, relays, amount and e', () {
      final pubkey = List.filled(32, '11').join();
      final eventId = List.filled(32, '22').join();
      final tags = buildZapRequestTags(
        recipientPubkeyHex: pubkey,
        amountMsats: 21000,
        relays: ['wss://nos.lol'],
        eventId: eventId,
      );
      expect(tags, contains(equals(['p', pubkey])));
      expect(tags, contains(equals(['amount', '21000'])));
      expect(tags, contains(equals(['e', eventId])));
      expect(
        tags,
        contains(equals(['relays', 'wss://nos.lol'])),
      );
    });
  });

  group('Monero', () {
    const valid =
        '47MejNNfkM939AbAsaNMWX3Scf87G5LzLPoFfaDsV8oiLhyj3CrMxGDebVKN6JLz38aJJjucDr9fBUZAMtVknmGPGUZM6LX';

    test('validates addresses', () {
      expect(isValidMoneroAddress(valid), isTrue);
      expect(isValidMoneroAddress('4abc'), isFalse);
      expect(isValidMoneroAddress('17${'1' * 93}'), isFalse);
      expect(
        isValidMoneroAddress(valid.replaceRange(0, 1, '0')),
        isFalse,
      );
    });

    test('validates XMR amounts', () {
      expect(normalizeXmrAmount('0.1'), '0.1');
      expect(normalizeXmrAmount('1.1000'), '1.1');
      expect(() => normalizeXmrAmount('0'), throwsFormatException);
      expect(() => normalizeXmrAmount('abc'), throwsFormatException);
      expect(
          () => normalizeXmrAmount('1.1234567890123'), throwsFormatException);
    });

    test('builds a payment URI', () {
      final uri = buildMoneroUri(
        address: valid,
        amountXmr: '0.1',
        description: 'thanks',
      );
      final parsed = Uri.parse(uri);
      expect(parsed.scheme, 'monero');
      expect(parsed.queryParameters['tx_amount'], '0.1');
      expect(parsed.queryParameters['tx_description'], 'thanks');
    });
  });
}
