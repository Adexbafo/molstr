// ignore_for_file: experimental_member_use
import 'dart:convert';

import 'package:ndk/shared/nips/nip44/nip44.dart' as nip44;
import 'package:shared_preferences/shared_preferences.dart';

import 'identity_service.dart';
import 'nostr_event.dart';
import 'relay_service.dart';

/// NIP-51 pinned notes. Public; shown on the owner's profile.
const int kPinListKind = 10001;

/// NIP-51 bookmarks. MolStr stores its own items privately (encrypted).
const int kBookmarkListKind = 10003;

enum ListUpdateResult {
  published,
  noIdentity,
  unknownState,
  unreadable,
  rejected
}

/// Returns [tags] with `['e', eventId]` added or removed.
/// Every other tag is kept unchanged, including ones from other clients.
List<List<String>> toggleEventTag(
  List<List<String>> tags,
  String eventId, {
  required bool add,
}) {
  final id = eventId.toLowerCase();
  final kept = <List<String>>[
    for (final tag in tags)
      if (!(tag.length >= 2 && tag[0] == 'e' && tag[1].toLowerCase() == id))
        List<String>.of(tag),
  ];
  if (add) kept.add(['e', id]);
  return kept;
}

/// The note ids referenced by `e` tags.
Set<String> eventIdsIn(List<List<String>> tags) => {
      for (final tag in tags)
        if (tag.length >= 2 && tag[0] == 'e') tag[1].toLowerCase(),
    };

/// Encrypts private list items to the owner's own key (NIP-44).
Future<String> encryptPrivateTags(
  List<List<String>> tags,
  String privateKeyHex,
  String pubkeyHex,
) {
  return nip44.Nip44.encryptMessage(jsonEncode(tags), privateKeyHex, pubkeyHex);
}

/// Decrypts private list items. Returns null if the content cannot be read,
/// for example a list encrypted with the older NIP-04 format.
Future<List<List<String>>?> decryptPrivateTags(
  String content,
  String privateKeyHex,
  String pubkeyHex,
) async {
  if (content.contains('?iv=')) return null; // NIP-04, not supported yet.
  try {
    final plain =
        await nip44.Nip44.decryptMessage(content, privateKeyHex, pubkeyHex);
    final decoded = jsonDecode(plain);
    if (decoded is! List) return null;
    final tags = <List<String>>[];
    for (final tag in decoded) {
      if (tag is! List) return null;
      tags.add([for (final item in tag) '$item']);
    }
    return tags;
  } catch (_) {
    return null;
  }
}

class NostrListService {
  NostrListService({
    required this.identityService,
    required this.relayService,
    required this.preferences,
  });

  final IdentityService identityService;
  final RelayService relayService;
  final SharedPreferences preferences;

  static const _cachePrefix = 'molstr.lists.v1.';

  String _key(String me, int kind) => '$_cachePrefix$kind.$me';

  /// Ids MolStr last saw in this list, for drawing icons without a network call.
  Set<String> cachedIds(String me, int kind) =>
      (preferences.getStringList(_key(me, kind)) ?? const []).toSet();

  Future<void> _cache(String me, int kind, Set<String> ids) =>
      preferences.setStringList(_key(me, kind), ids.toList());

  /// Newest copy of the list. `known` is false when the relays could not
  /// confirm what the list contains, so it must not be overwritten.
  Future<({NostrEvent? event, bool known})> _loadLatest(
    String me,
    int kind,
    List<String> relays,
  ) async {
    final query = await relayService.queryEvents(
      {
        'kinds': [kind],
        'authors': [me],
        'limit': 5,
      },
      relays,
    );
    if (!query.reachedRelay) return (event: null, known: false);

    final events = query.events
        .where((e) => e.kind == kind && e.pubkey == me)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (events.isEmpty) {
      // "No list" is only trustworthy when every relay answered.
      return (event: null, known: query.respondingRelays >= relays.length);
    }
    return (event: events.first, known: true);
  }

  /// Reads the list from relays and refreshes the local cache.
  /// Returns null if the list could not be confirmed.
  Future<Set<String>?> sync({
    required int kind,
    required List<String> relays,
  }) async {
    final me = await identityService.currentIdentity();
    if (me == null) return null;

    final state = await _loadLatest(me.pubkey, kind, relays);
    if (!state.known) return null;

    final latest = state.event;
    if (latest == null) {
      await _cache(me.pubkey, kind, <String>{});
      return <String>{};
    }

    final ids = eventIdsIn(latest.tags);
    if (latest.content.isNotEmpty) {
      final privateKey = await identityService.currentNsecHex();
      if (privateKey != null) {
        final hidden =
            await decryptPrivateTags(latest.content, privateKey, me.pubkey);
        if (hidden != null) ids.addAll(eventIdsIn(hidden));
      }
    }

    await _cache(me.pubkey, kind, ids);
    return ids;
  }

  /// Adds or removes one note. With [private] true the note is stored in the
  /// encrypted part of the list; otherwise in the public tags.
  Future<ListUpdateResult> toggle({
    required int kind,
    required String eventId,
    required bool add,
    required List<String> relays,
    bool private = false,
  }) async {
    final me = await identityService.currentIdentity();
    if (me == null) return ListUpdateResult.noIdentity;

    final privateKey = await identityService.currentNsecHex();
    if (privateKey == null) return ListUpdateResult.noIdentity;

    final state = await _loadLatest(me.pubkey, kind, relays);
    if (!state.known) return ListUpdateResult.unknownState;

    final latest = state.event;
    var publicTags = <List<String>>[
      for (final tag in latest?.tags ?? const <List<String>>[])
        List<String>.of(tag),
    ];
    var privateTags = <List<String>>[];

    if (latest != null && latest.content.isNotEmpty) {
      final hidden =
          await decryptPrivateTags(latest.content, privateKey, me.pubkey);
      if (hidden == null) return ListUpdateResult.unreadable;
      privateTags = hidden;
    }

    // Remove from both parts, then add to the chosen part.
    publicTags = toggleEventTag(publicTags, eventId, add: false);
    privateTags = toggleEventTag(privateTags, eventId, add: false);
    if (add) {
      if (private) {
        privateTags = toggleEventTag(privateTags, eventId, add: true);
      } else {
        publicTags = toggleEventTag(publicTags, eventId, add: true);
      }
    }

    final content = privateTags.isEmpty
        ? ''
        : await encryptPrivateTags(privateTags, privateKey, me.pubkey);

    final event = await identityService.signEvent(
      kind: kind,
      content: content,
      tags: publicTags,
    );
    final results = await relayService.publishEvent(event, relays);
    final ok = results.values.where((value) => value == 'ok').length;
    if (ok == 0) return ListUpdateResult.rejected;

    await _cache(
      me.pubkey,
      kind,
      {...eventIdsIn(publicTags), ...eventIdsIn(privateTags)},
    );
    return ListUpdateResult.published;
  }
}
