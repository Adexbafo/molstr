import 'package:shared_preferences/shared_preferences.dart';

import 'identity_service.dart';
import 'nostr_event.dart';
import 'relay_service.dart';

const int kRelayListKind = 10002;

class UserRelayList {
  const UserRelayList({
    required this.readRelays,
    required this.writeRelays,
    required this.updatedAt,
  });

  final List<String> readRelays;
  final List<String> writeRelays;
  final int updatedAt;

  bool get isEmpty => readRelays.isEmpty && writeRelays.isEmpty;

  /// Deduplicated list of relays appropriate for reading events from this
  /// user. If the author declared no read relays, their write relays are
  /// included so we can still find their notes.
  List<String> relaysForReading() {
    final combined = <String>{...writeRelays, ...readRelays};
    return combined.toList();
  }

  /// Deduplicated list of relays appropriate for sending events to reach
  /// this user. If the author declared no read relays, fall back to their
  /// write relays as a best effort.
  List<String> relaysForSending() {
    if (readRelays.isNotEmpty) return readRelays;
    return writeRelays;
  }
}

/// Parses a kind 10002 event. Invalid, duplicate, or insecure entries are
/// skipped. ws:// is only accepted for localhost, matching the rule in
/// RelayService.normalizeRelayUrl.
UserRelayList parseRelayListEvent(NostrEvent event) {
  if (event.kind != kRelayListKind) {
    return UserRelayList(
      readRelays: const [],
      writeRelays: const [],
      updatedAt: event.createdAt,
    );
  }

  final read = <String>{};
  final write = <String>{};

  for (final tag in event.tags) {
    if (tag.length < 2 || tag[0] != 'r') continue;

    final String normalized;
    try {
      normalized = RelayService.normalizeRelayUrl(tag[1]);
    } on FormatException {
      continue;
    }

    final marker = tag.length >= 3 ? tag[2].toLowerCase() : '';
    if (marker.isEmpty) {
      read.add(normalized);
      write.add(normalized);
    } else if (marker == 'read') {
      read.add(normalized);
    } else if (marker == 'write') {
      write.add(normalized);
    }
  }

  return UserRelayList(
    readRelays: read.toList(),
    writeRelays: write.toList(),
    updatedAt: event.createdAt,
  );
}

/// Chooses the newest verified kind 10002 event, if any.
UserRelayList? pickLatestRelayList(List<NostrEvent> events) {
  final filtered = events.where((e) => e.kind == kRelayListKind).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  if (filtered.isEmpty) return null;
  return parseRelayListEvent(filtered.first);
}

class UserRelayService {
  UserRelayService({
    required this.relayService,
    required this.identityService,
    required this.preferences,
  });

  final RelayService relayService;
  final IdentityService identityService;
  final SharedPreferences preferences;

  static const _globalKey = 'molstr.relays.global';
  static const _cacheKeyPrefix = 'molstr.relays.user.';

  List<String> loadGlobalRelays() {
    return preferences.getStringList(_globalKey) ?? const [];
  }

  Future<void> saveGlobalRelays(List<String> relays) async {
    final cleaned = <String>[];
    final seen = <String>{};
    for (final raw in relays) {
      try {
        final normalized = RelayService.normalizeRelayUrl(raw);
        if (seen.add(normalized)) cleaned.add(normalized);
      } on FormatException {
        // skip invalid entries
      }
    }
    await preferences.setStringList(_globalKey, cleaned);
  }

  /// Returns the author's relay list using the broadest set of relays we
  /// currently know about: your selected relays plus your global relays.
  /// If no relay responds, returns null.
  Future<UserRelayList?> fetchRelayList({
    required String pubkey,
    required List<String> selectedRelays,
  }) async {
    final queryRelays = <String>{...selectedRelays, ...loadGlobalRelays()};
    if (queryRelays.isEmpty) return null;

    final query = await relayService.queryEvents(
      {
        'kinds': [kRelayListKind],
        'authors': [pubkey.toLowerCase()],
        'limit': 5,
      },
      queryRelays.toList(),
    );

    if (!query.reachedRelay) return null;
    final list = pickLatestRelayList(query.events);
    if (list != null) {
      await preferences.setStringList(
        '$_cacheKeyPrefix${pubkey.toLowerCase()}',
        [
          ...list.readRelays.map((r) => 'read\u0001$r'),
          ...list.writeRelays.map((r) => 'write\u0001$r'),
        ],
      );
    }
    return list;
  }

  /// Published list for [pubkey] from the local cache, if any.
  UserRelayList? cachedRelayList(String pubkey) {
    final entries =
        preferences.getStringList('$_cacheKeyPrefix${pubkey.toLowerCase()}');
    if (entries == null || entries.isEmpty) return null;

    final read = <String>[];
    final write = <String>[];
    for (final entry in entries) {
      final parts = entry.split('\u0001');
      if (parts.length != 2) continue;
      if (parts[0] == 'read') {
        read.add(parts[1]);
      } else if (parts[0] == 'write') {
        write.add(parts[1]);
      }
    }
    return UserRelayList(
      readRelays: read,
      writeRelays: write,
      updatedAt: 0,
    );
  }

  /// Signs and publishes a kind 10002 event for the active identity.
  /// Returns relay URL -> status.
  Future<Map<String, String>> publishOwnRelayList({
    required List<String> readRelays,
    required List<String> writeRelays,
    required List<String> publishRelays,
  }) async {
    final me = await identityService.currentIdentity();
    if (me == null) {
      throw StateError('Connect a key in Profile to publish a relay list.');
    }
    if (publishRelays.isEmpty) {
      throw StateError('No relays are configured.');
    }

    String clean(String value) => RelayService.normalizeRelayUrl(value);

    final cleanedRead = <String>{};
    for (final r in readRelays) {
      cleanedRead.add(clean(r));
    }
    final cleanedWrite = <String>{};
    for (final r in writeRelays) {
      cleanedWrite.add(clean(r));
    }

    final tags = <List<String>>[];
    final both = cleanedRead.intersection(cleanedWrite);
    for (final url in both) {
      tags.add(['r', url]);
    }
    for (final url in cleanedRead.difference(both)) {
      tags.add(['r', url, 'read']);
    }
    for (final url in cleanedWrite.difference(both)) {
      tags.add(['r', url, 'write']);
    }

    final event = await identityService.signEvent(
      kind: kRelayListKind,
      content: '',
      tags: tags,
    );
    return relayService.publishEvent(event, publishRelays);
  }
}
