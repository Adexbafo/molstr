import 'dart:async';

import 'package:flutter/foundation.dart';

/// Watches a note's zap total after you close a zap sheet, so the note card
/// updates when a receipt appears, without a manual refresh.
///
/// Totals come from the normal engagement query, which counts only receipts
/// that validate against a signed zap request. A watch never marks a payment
/// as complete on its own.
class ZapWatch extends ChangeNotifier {
  ZapWatch({
    this.interval = const Duration(seconds: 10),
    this.limit = const Duration(minutes: 2),
  });

  /// The shared instance used by the note cards.
  static final ZapWatch instance = ZapWatch();

  /// How often the zap total is re-read while a watch is running.
  final Duration interval;

  /// How long a watch runs before giving up.
  final Duration limit;

  final Map<String, int> _observed = {};
  final Map<String, Timer> _timers = {};

  /// The highest zap total seen for [noteId] during this session.
  int observedFor(String noteId) => _observed[noteId] ?? 0;

  /// Whether a watch for [noteId] is still running.
  bool isPending(String noteId) => _timers.containsKey(noteId);

  /// Re-reads the total with [fetchTotal] until it rises above [baseline],
  /// then stops. Gives up after [limit]. Starting a new watch for the same
  /// note replaces the old one.
  void watch({
    required String noteId,
    required int baseline,
    required Future<int> Function() fetchTotal,
  }) {
    _timers.remove(noteId)?.cancel();

    final startedAt = DateTime.now();
    var busy = false;
    late final Timer timer;

    // Only the newest watch for a note may act on its results.
    bool isCurrent() => identical(_timers[noteId], timer);

    Future<void> poll() async {
      if (busy || !isCurrent()) return;
      busy = true;
      int? total;
      try {
        total = await fetchTotal();
      } catch (_) {
        // A failed query is tried again on the next tick.
        total = null;
      } finally {
        busy = false;
      }

      if (!isCurrent()) return;
      if (total != null && total > baseline) {
        _record(noteId, total);
        _stop(noteId);
      }
    }

    timer = Timer.periodic(interval, (_) {
      if (!isCurrent()) return;
      if (DateTime.now().difference(startedAt) >= limit) {
        _stop(noteId);
        return;
      }
      unawaited(poll());
    });
    _timers[noteId] = timer;
    notifyListeners();
    unawaited(poll());
  }

  /// Cancels every running watch. Used by tests.
  @visibleForTesting
  void cancelAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  void _record(String noteId, int total) {
    if (total > (_observed[noteId] ?? 0)) {
      _observed[noteId] = total;
    }
    notifyListeners();
  }

  void _stop(String noteId) {
    _timers.remove(noteId)?.cancel();
    notifyListeners();
  }
}
