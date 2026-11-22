import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/nostr_event.dart';
import 'package:molstr/core/nostr/relay_service.dart';

void main() {
  test('signed NostrEvent passes NIP-01 and BIP-340 verification', () {
    final privHex = List.filled(32, '1a').join();
    final event = NostrEvent.sign(
      privateKeyHex: privHex,
      kind: 1,
      content: 'Hello from MolStr!',
      createdAt: 1700000000,
    );

    expect(event.verify(), isTrue);
    expect(NostrEvent.fromJsonVerified(event.toJson()), isNotNull);
  });

  test('tampered content fails verification', () {
    final privHex = List.filled(32, '2b').join();
    final event = NostrEvent.sign(
      privateKeyHex: privHex,
      kind: 1,
      content: 'Original note',
      createdAt: 1700000000,
    );

    final tampered = Map<String, dynamic>.from(event.toJson())
      ..['content'] = 'Forged by untrusted relay';

    expect(NostrEvent.fromJsonVerified(tampered), isNull);
  });

  test('relay URL validation enforces wss for remote relays', () {
    expect(
      RelayService.normalizeRelayUrl('wss://nos.lol/'),
      'wss://nos.lol',
    );
    expect(
      RelayService.normalizeRelayUrl('ws://127.0.0.1:7777/'),
      'ws://127.0.0.1:7777',
    );
    expect(
      () => RelayService.normalizeRelayUrl('ws://nos.lol'),
      throwsA(isA<FormatException>()),
    );
  });

  test('poll event parses options, polltype and endsAt', () {
    final event = NostrEvent.sign(
      privateKeyHex: List.filled(32, '4c').join(),
      kind: 1068,
      content: 'Best chain?',
      tags: [
        ['option', '0', 'Bitcoin'],
        ['option', '1', 'Monero'],
        ['polltype', 'singlechoice'],
        ['endsAt', '1900000000'],
      ],
      createdAt: 1700000000,
    );

    final poll = PollData.fromEvent(event)!;
    expect(poll.options.length, 2);
    expect(poll.options[0].label, 'Bitcoin');
    expect(poll.multipleChoice, isFalse);
    expect(poll.endsAt, 1900000000);
  });

  test('article event parses title and d tag', () {
    final event = NostrEvent.sign(
      privateKeyHex: List.filled(32, '5d').join(),
      kind: 30023,
      content: '# Hello\n\nBody text.',
      tags: [
        ['title', 'My Article'],
        ['d', 'my-article-1'],
      ],
      createdAt: 1700000000,
    );

    final article = ArticleData.fromEvent(event)!;
    expect(article.title, 'My Article');
    expect(article.d, 'my-article-1');
    expect(event.dTag, 'my-article-1');
  });
}
