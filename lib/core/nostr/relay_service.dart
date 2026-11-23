import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'nostr_event.dart';
import 'note_engagement.dart';

class FeedResult {
  const FeedResult({
    required this.notes,
    required this.profiles,
    required this.noteRelays,
    required this.connectedRelays,
    required this.failedRelays,
    this.polls = const [],
    this.articles = const [],
  });

  final List<NostrEvent> notes;
  final List<NostrEvent> polls;
  final List<NostrEvent> articles;
  final Map<String, ProfileMetadata> profiles;
  final Map<String, Set<String>> noteRelays;
  final List<String> connectedRelays;
  final List<String> failedRelays;
}

class _RawEvent {
  const _RawEvent(this.json, this.relay);
  final Map<String, dynamic> json;
  final String relay;
}

class _VerifiedEvent {
  const _VerifiedEvent(this.event, this.relay);
  final NostrEvent event;
  final String relay;
}

/// Runs in a background isolate so slow pure-Dart verification
/// never blocks the UI thread.
List<_VerifiedEvent> _verifyRawEvents(List<_RawEvent> rawEvents) {
  final result = <_VerifiedEvent>[];

  for (final raw in rawEvents) {
    final event = NostrEvent.fromJsonVerified(raw.json);
    if (event != null) {
      result.add(_VerifiedEvent(event, raw.relay));
    }
  }

  return result;
}

class RelayService {
  RelayService({SharedPreferences? preferences}) : _preferences = preferences;

  static const _relaysKey = 'nostr.relays';

  static const defaultRelays = <String>[
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.primal.net',
  ];

  final SharedPreferences? _preferences;

  List<String> loadRelays() {
    final stored = _preferences?.getStringList(_relaysKey);
    if (stored == null) {
      return List<String>.from(defaultRelays);
    }
    return List<String>.from(stored);
  }

  Future<void> saveRelays(List<String> relays) async {
    final prefs = _preferences;
    if (prefs == null) {
      throw StateError('Preferences unavailable');
    }
    final saved = await prefs.setStringList(_relaysKey, relays);
    if (!saved) {
      throw StateError('Could not save relay list');
    }
  }

  /// Publishes [event] to [relays] and returns relay -> status.
  /// 'ok' means the relay accepted it (NIP-01 ["OK", id, true, msg]).
  Future<Map<String, String>> publishEvent(
    NostrEvent event,
    List<String> relays, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final results = <String, String>{};

    await Future.wait(relays.map((relayUrl) async {
      WebSocketChannel? channel;
      StreamSubscription<dynamic>? subscription;

      try {
        channel = WebSocketChannel.connect(Uri.parse(relayUrl));
        final ready = channel.ready;
        ready.ignore();
        await ready.timeout(timeout);

        final done = Completer<String>();

        subscription = channel.stream.listen(
          (raw) {
            if (raw is! String || done.isCompleted) return;
            try {
              final message = jsonDecode(raw);
              if (message is List &&
                  message.length >= 3 &&
                  message[0] == 'OK' &&
                  message[1] == event.id) {
                final accepted = message[2] == true;
                final reason = message.length > 3 && message[3] is String
                    ? message[3] as String
                    : '';
                done.complete(
                  accepted
                      ? 'ok'
                      : (reason.isEmpty ? 'rejected' : 'rejected: $reason'),
                );
              }
            } catch (_) {}
          },
          onError: (_) {
            if (!done.isCompleted) done.complete('failed');
          },
          onDone: () {
            if (!done.isCompleted) done.complete('connection closed');
          },
        );

        channel.sink.add(jsonEncode(['EVENT', event.toJson()]));

        results[relayUrl] =
            await done.future.timeout(timeout, onTimeout: () => 'timeout');
        debugPrint('MolStr: publish -> $relayUrl: ${results[relayUrl]}');
      } catch (error) {
        results[relayUrl] = 'failed';
        debugPrint('MolStr: publish failed on $relayUrl: $error');
      } finally {
        unawaited(subscription?.cancel());
        final sink = channel?.sink;
        if (sink != null) {
          try {
            sink.add(jsonEncode(['CLOSE', event.id]));
          } catch (_) {}
          unawaited(sink.close().catchError((_) {}));
        }
      }
    }));

    return results;
  }

  static String normalizeRelayUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Enter a relay URL.');
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      throw const FormatException('Invalid relay URL.');
    }

    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final isLoopback =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';

    if (scheme != 'wss' && !(scheme == 'ws' && isLoopback)) {
      throw const FormatException(
        'Use wss:// for remote relays (ws:// is only allowed for localhost).',
      );
    }

    if (uri.userInfo.isNotEmpty || uri.hasFragment) {
      throw const FormatException(
        'Relay URL must not include credentials or #fragments.',
      );
    }

    final formattedHost = host.contains(':') ? '[$host]' : host;
    final normalizedPath = uri.path == '/' ? '' : uri.path;
    final portPart = uri.hasPort ? ':${uri.port}' : '';
    final queryPart = uri.hasQuery ? '?${uri.query}' : '';

    return '$scheme://$formattedHost$portPart$normalizedPath$queryPart';
  }

  /// Fetches kind-1 replies that reference [eventId], oldest first.
  Future<FeedResult> fetchThread(String eventId, List<String> relays) async {
    final connected = <String>[];
    final failed = <String>[];
    final raw = <_RawEvent>[];

    await Future.wait(relays.map((relayUrl) async {
      try {
        final events = await _queryRelay(
          relayUrl,
          {
            'kinds': [1],
            '#e': [eventId],
            'limit': 100,
          },
          timeout: const Duration(seconds: 6),
        ).timeout(const Duration(seconds: 12));
        connected.add(relayUrl);
        raw.addAll(events.map((e) => _RawEvent(e, relayUrl)));
      } catch (error) {
        failed.add(relayUrl);
        debugPrint('MolStr: thread query on $relayUrl failed: $error');
      }
    }));

    final verified = await compute(_verifyRawEvents, raw);
    final byId = <String, NostrEvent>{};
    final noteRelays = <String, Set<String>>{};
    for (final item in verified) {
      if (item.event.kind != 1) continue;
      byId.putIfAbsent(item.event.id, () => item.event);
      noteRelays.putIfAbsent(item.event.id, () => <String>{}).add(item.relay);
    }

    final replies = byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final profiles = await _fetchProfiles(
      connected,
      replies.map((e) => e.pubkey).toSet().take(50).toList(),
    );

    debugPrint('MolStr: thread $eventId has ${replies.length} replies');

    return FeedResult(
      notes: replies,
      profiles: profiles,
      noteRelays: noteRelays,
      connectedRelays: connected,
      failedRelays: failed,
    );
  }

  Future<Map<String, NoteEngagement>> fetchNoteEngagement(
    Iterable<String> noteIds,
    List<String> relays,
  ) async {
    // One batched request per relay, never one connection per note.
    final ids = noteIds.toSet().take(60).toList();
    if (ids.isEmpty || relays.isEmpty) return const {};

    final raw = <_RawEvent>[];
    var respondingRelays = 0;

    await Future.wait(relays.map((relayUrl) async {
      try {
        final events = await _queryRelay(
          relayUrl,
          {
            'kinds': [1, 6, 7],
            '#e': ids,
            'limit': 300,
          },
          timeout: const Duration(seconds: 5),
        ).timeout(const Duration(seconds: 9));

        raw.addAll(events.map((event) => _RawEvent(event, relayUrl)));
        respondingRelays++;
      } catch (error) {
        debugPrint(
          'MolStr: interaction query on $relayUrl failed: $error',
        );
      }
    }));

    // No response is unknown, not zero interactions.
    if (respondingRelays == 0) return const {};

    final verified = await compute(_verifyRawEvents, raw);
    final counts = tallyNoteEngagement(
      noteIds: ids,
      verifiedEvents: verified.map((item) => item.event),
    );

    debugPrint(
      'MolStr: counted ${verified.length} verified interaction deliveries '
      'for ${ids.length} notes',
    );

    return counts;
  }

  Future<Map<String, ProfileMetadata>> _fetchProfiles(
    List<String> relays,
    List<String> authors,
  ) async {
    final profiles = <String, ProfileMetadata>{};
    if (relays.isEmpty || authors.isEmpty) return profiles;

    final raw = <_RawEvent>[];
    await Future.wait(relays.map((relayUrl) async {
      try {
        final events = await _queryRelay(
          relayUrl,
          {
            'kinds': [0],
            'authors': authors,
          },
          timeout: const Duration(seconds: 4),
        ).timeout(const Duration(seconds: 8));
        raw.addAll(events.map((e) => _RawEvent(e, relayUrl)));
      } catch (error) {
        debugPrint('MolStr: profile query on $relayUrl failed: $error');
      }
    }));

    final verified = await compute(_verifyRawEvents, raw);
    for (final item in verified) {
      final profile = ProfileMetadata.fromKind0(item.event);
      if (profile == null) continue;
      final existing = profiles[profile.pubkey];
      if (existing == null || profile.createdAt > existing.createdAt) {
        profiles[profile.pubkey] = profile;
      }
    }
    return profiles;
  }

  Future<FeedResult> fetchFeed(
    List<String> relays, {
    int limit = 20,
    void Function(String status)? onStatus,
    List<String>? authors,
  }) async {
    final connectedRelays = <String>[];
    final failedRelays = <String>[];
    final rawNotes = <_RawEvent>[];

    onStatus?.call('Connecting to ${relays.length} relay(s)...');

    await Future.wait(
      relays.map((relayUrl) async {
        try {
          final filter = <String, dynamic>{
            'kinds': [1, 1068, 30023],
            'limit': limit,
          };
          if (authors != null) {
            filter['authors'] = authors;
          }
          final events = await _queryRelay(
            relayUrl,
            filter,
            timeout: const Duration(seconds: 6),
          ).timeout(const Duration(seconds: 12));

          connectedRelays.add(relayUrl);
          rawNotes.addAll(events.map((e) => _RawEvent(e, relayUrl)));
          debugPrint('MolStr: $relayUrl returned ${events.length} notes');
        } catch (error) {
          failedRelays.add(relayUrl);
          debugPrint('MolStr: $relayUrl failed: $error');
        }
      }),
    );

    onStatus?.call('Verifying ${rawNotes.length} notes...');
    final verifiedNotes = await compute(_verifyRawEvents, rawNotes);

    final notesById = <String, NostrEvent>{};
    final pollsById = <String, NostrEvent>{};
    final articlesByKey = <String, NostrEvent>{};
    final noteRelays = <String, Set<String>>{};

    for (final item in verifiedNotes) {
      final event = item.event;
      noteRelays.putIfAbsent(event.id, () => <String>{}).add(item.relay);

      switch (event.kind) {
        case 1:
          notesById.putIfAbsent(event.id, () => event);
        case 1068:
          pollsById.putIfAbsent(event.id, () => event);
        case 30023:
          // Parametrized replaceable: dedupe by author + d tag, newest wins.
          final key = '${event.pubkey}|${event.dTag}';
          final existing = articlesByKey[key];
          if (existing == null || event.createdAt > existing.createdAt) {
            articlesByKey[key] = event;
          }
      }
    }

    final notes = notesById.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final polls = pollsById.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final articles = articlesByKey.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    debugPrint(
      'MolStr: ${notes.length} notes, ${polls.length} polls, '
      '${articles.length} articles from ${rawNotes.length} raw',
    );

    // Authors are computed AFTER notes exist, then used for the kind-0 query.
    final profileAuthors = authors != null
        ? authors.toSet().toList()
        : <String>{
            ...notes.map((n) => n.pubkey),
            ...polls.map((p) => p.pubkey),
            ...articles.map((a) => a.pubkey),
          }.take(50).toList();

    onStatus?.call('Loading ${profileAuthors.length} author profiles...');
    final profiles = await _fetchProfiles(connectedRelays, profileAuthors);

    return FeedResult(
      notes: notes,
      polls: polls,
      articles: articles,
      profiles: profiles,
      noteRelays: noteRelays,
      connectedRelays: connectedRelays,
      failedRelays: failedRelays,
    );
  }

  /// Collects raw event JSON from one relay. No verification here;
  /// that happens later in a background isolate.
  Future<List<Map<String, dynamic>>> _queryRelay(
    String relayUrl,
    Map<String, dynamic> filter, {
    required Duration timeout,
  }) async {
    final channel = WebSocketChannel.connect(Uri.parse(relayUrl));
    final events = <Map<String, dynamic>>[];
    final subId = 'molstr${DateTime.now().microsecondsSinceEpoch}';
    final done = Completer<void>();
    StreamSubscription<dynamic>? subscription;

    void finish() {
      if (!done.isCompleted) done.complete();
    }

    try {
      await channel.ready.timeout(timeout);

      subscription = channel.stream.listen(
        (raw) {
          if (raw is! String) return;
          try {
            final message = jsonDecode(raw);
            if (message is! List || message.length < 2) return;
            final type = message[0];

            if (type == 'EVENT' && message.length >= 3 && message[1] == subId) {
              final rawEvent = message[2];
              if (rawEvent is Map<String, dynamic>) {
                events.add(rawEvent);
              }
            } else if ((type == 'EOSE' || type == 'CLOSED') &&
                message[1] == subId) {
              finish();
            }
          } catch (_) {
            // Ignore malformed messages from untrusted relays.
          }
        },
        onError: (_) => finish(),
        onDone: finish,
      );

      channel.sink.add(jsonEncode(['REQ', subId, filter]));

      await done.future.timeout(timeout, onTimeout: () {});

      try {
        channel.sink.add(jsonEncode(['CLOSE', subId]));
      } catch (_) {}
    } finally {
      // Never await socket teardown: a hanging close must not stall the feed.
      unawaited(subscription?.cancel());
      unawaited(channel.sink.close().catchError((_) {}));
    }

    return events;
  }
}
