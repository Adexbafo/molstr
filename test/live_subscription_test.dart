import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/live_subscription.dart';

void main() {
  test('reconnect delay doubles and caps at 60 seconds', () {
    expect(reconnectDelay(1), const Duration(seconds: 2));
    expect(reconnectDelay(2), const Duration(seconds: 4));
    expect(reconnectDelay(3), const Duration(seconds: 8));
    expect(reconnectDelay(50), const Duration(seconds: 60));
  });

  test('gift wrap filter reaches back past the two-day backdating window', () {
    final filter = giftWrapLiveFilter('AB' * 32);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    expect(filter['kinds'], [1059]);
    expect(filter['#p'], ['ab' * 32]);
    expect(filter['since'] as int, lessThan(now - 2 * 24 * 60 * 60));
  });
}
