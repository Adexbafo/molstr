import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/payments/zap_watch.dart';

void main() {
  const noteId = 'note-under-test';

  ZapWatch quickWatch({Duration limit = const Duration(seconds: 2)}) {
    return ZapWatch(
      interval: const Duration(milliseconds: 5),
      limit: limit,
    );
  }

  test('records the total once it rises above the baseline', () async {
    final zap = quickWatch();
    addTearDown(zap.cancelAll);

    var calls = 0;
    zap.watch(
      noteId: noteId,
      baseline: 0,
      fetchTotal: () async {
        calls++;
        return calls < 3 ? 0 : 21;
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(zap.observedFor(noteId), 21);
    expect(zap.isPending(noteId), isFalse);
  });

  test('a failed relay query does not end the watch', () async {
    final zap = quickWatch();
    addTearDown(zap.cancelAll);

    var calls = 0;
    zap.watch(
      noteId: noteId,
      baseline: 0,
      fetchTotal: () async {
        calls++;
        if (calls <= 2) {
          throw Exception('relay timeout');
        }
        return 21;
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(zap.observedFor(noteId), 21);
  });

  test('gives up after the limit when no receipt appears', () async {
    final zap = quickWatch(limit: const Duration(milliseconds: 60));
    addTearDown(zap.cancelAll);

    zap.watch(
      noteId: noteId,
      baseline: 0,
      fetchTotal: () async => 0,
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(zap.observedFor(noteId), 0);
    expect(zap.isPending(noteId), isFalse);
  });

  test('a total equal to the baseline is not treated as new', () async {
    final zap = quickWatch(limit: const Duration(milliseconds: 60));
    addTearDown(zap.cancelAll);

    zap.watch(
      noteId: noteId,
      baseline: 21,
      fetchTotal: () async => 21,
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(zap.observedFor(noteId), 0);
  });
}
