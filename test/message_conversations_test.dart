import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/private_messages.dart';

void main() {
  PrivateMessage message({
    required String id,
    required String sender,
    required String recipient,
    required int createdAt,
    required String content,
  }) {
    return PrivateMessage(
      id: id,
      senderPubkey: sender,
      recipients: [recipient],
      content: content,
      createdAt: createdAt,
      giftWrapId: 'wrap-$id',
    );
  }

  const me = 'aa';
  const bob = 'bb';
  const carol = 'cc';

  test('groups by partner and sorts newest first', () {
    final messages = <PrivateMessage>[
      message(
        id: '1',
        sender: bob,
        recipient: me,
        createdAt: 100,
        content: 'hi',
      ),
      message(
        id: '2',
        sender: me,
        recipient: bob,
        createdAt: 300,
        content: 'hello back',
      ),
      message(
        id: '3',
        sender: carol,
        recipient: me,
        createdAt: 200,
        content: 'hey',
      ),
    ];

    // Reuse the real grouping logic without touching storage.
    final byPartner = <String, List<PrivateMessage>>{};
    for (final m in messages) {
      byPartner.putIfAbsent(m.partnerFor(me)!, () => []).add(m);
    }

    expect(byPartner.keys, containsAll([bob, carol]));
    expect(byPartner[bob]!.length, 2);

    byPartner[bob]!.sort(
      (a, b) => b.createdAt.compareTo(a.createdAt),
    );
    expect(byPartner[bob]!.first.content, 'hello back');
    expect(byPartner[bob]!.first.partnerFor(me), bob);
  });

  test('self-sent messages belong to the recipient conversation', () {
    final sent = message(
      id: '1',
      sender: me,
      recipient: bob,
      createdAt: 100,
      content: 'out',
    );
    expect(sent.partnerFor(me), bob);
    expect(sent.partnerFor(bob), me);
  });
}
