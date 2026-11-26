import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'nostr_event.dart';

/// Delay before reconnecting after [attempt] failures: 2s, 4s, 8s ... max 60s.
Duration reconnectDelay(int attempt) {
  final seconds = min(60, 1 << min(attempt, 6));
  return Duration(seconds: seconds);
}

int _unixNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// Gift wraps (kind 1059) for [pubkey]. NIP-59 backdates wrap timestamps by
/// up to two days, so the window must reach back further than "now".
Map<String, dynamic> giftWrapLiveFilter(String pubkey) => {
      'kinds': [1059],
      '#p': [pubkey.toLowerCase()],
      'since': _unixNow() - 3 * 24 * 60 * 60,
      'limit': 100,
    };

/// Interactions aimed at [pubkey]: replies, reposts, reactions, zaps, votes,
/// and follows. These are not backdated.
Map<String, dynamic> notificationLiveFilter(String pubkey) => {
      'kinds': [1, 3, 6, 7, 1018, 9735],
      '#p': [pubkey.toLowerCase()],
      'since': _unixNow() - 300,
      'limit': 100,
    };

/// Keeps one WebSocket per relay open with a single REQ, reconnects with
/// backoff, and reports each unique verified event once.
class LiveSubscription {
  LiveSubscription({
    required this.relays,
    required this.filter,
    required this.onEvent,
    this.onStatus,
  });

  final List<String> relays;
  final Map<String, dynamic> filter;

  /// Called once per unique verified event, with the relay that delivered it.
  final void Function(NostrEvent event, String relay) onEvent;

  /// Optional status for debugging, such as "connected".
  final void Function(String relay, String status)? onStatus;

  final String _subId = 'molstr-live-${DateTime.now().microsecondsSinceEpoch}';
  final Map<String, WebSocketChannel> _channels = {};
  final Map<String, StreamSubscription<dynamic>> _subs = {};
  final Map<String, Timer> _retryTimers = {};
  final Map<String, int> _failures = {};
  final Set<String> _seenIds = {};
  bool _running = false;

  bool get isRunning => _running;

  void start() {
    if (_running) return;
    _running = true;
    for (final relay in relays) {
      _connect(relay);
    }
  }

  void _connect(String relay) {
    if (!_running) return;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(relay));
      _channels[relay] = channel;
      _subs[relay] = channel.stream.listen(
        (raw) => _handle(relay, raw),
        onError: (_) => _scheduleReconnect(relay),
        onDone: () => _scheduleReconnect(relay),
      );
      channel.ready.then((_) {
        if (!_running || _channels[relay] != channel) return;
        _failures[relay] = 0;
        onStatus?.call(relay, 'connected');
        channel.sink.add(jsonEncode(['REQ', _subId, filter]));
      }).catchError((_) => _scheduleReconnect(relay));
    } catch (_) {
      _scheduleReconnect(relay);
    }
  }

  void _handle(String relay, dynamic raw) {
    if (raw is! String || !_running) return;
    try {
      final message = jsonDecode(raw);
      if (message is! List || message.length < 2) return;
      if (message[1] != _subId) return;

      if (message[0] == 'EVENT' && message.length >= 3) {
        final json = message[2];
        if (json is! Map<String, dynamic>) return;
        final id = json['id'];
        if (id is! String) return;
        if (!_seenIds.add(id)) return;
        if (_seenIds.length > 5000) _seenIds.clear();

        // Signature verification runs here. Volume is small for DMs and
        // notifications; move it to an isolate if this ever grows.
        final event = NostrEvent.fromJsonVerified(json);
        if (event != null) onEvent(event, relay);
      } else if (message[0] == 'CLOSED') {
        onStatus?.call(relay, 'closed by relay');
      }
    } catch (_) {
      // Ignore malformed messages from untrusted relays.
    }
  }

  void _scheduleReconnect(String relay) {
    if (!_running) return;
    if (_retryTimers[relay]?.isActive ?? false) return;

    _subs.remove(relay)?.cancel();
    _channels.remove(relay);

    final failures = (_failures[relay] ?? 0) + 1;
    _failures[relay] = failures;
    final delay = reconnectDelay(failures);
    onStatus?.call(relay, 'reconnecting in ${delay.inSeconds}s');

    _retryTimers[relay] = Timer(delay, () {
      _retryTimers.remove(relay);
      _connect(relay);
    });
  }

  void close() {
    _running = false;
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    for (final sub in _subs.values) {
      sub.cancel();
    }
    _subs.clear();
    for (final channel in _channels.values) {
      try {
        channel.sink.add(jsonEncode(['CLOSE', _subId]));
      } catch (_) {}
      channel.sink.close().catchError((_) {});
    }
    _channels.clear();
  }
}
