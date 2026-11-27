import 'nostr_event.dart';
import 'nostr_lists.dart';
import 'relay_service.dart';

/// Most pinned notes shown on a profile.
const int maxPinnedNotes = 10;

final _hexId = RegExp(r'^[0-9a-f]{64}$');

/// Note ids from the PUBLIC `e` tags of a pin list (kind 10001), newest pin
/// first. Encrypted content is ignored, because only public items belong on
/// a profile. Invalid ids and duplicates are skipped.
List<String> pinnedIdsFromList(NostrEvent list) {
  if (list.kind != kPinListKind) return const [];

  final ids = <String>[];
  final seen = <String>{};
  for (final tag in list.tags.reversed) {
    if (tag.length < 2 || tag[0] != 'e') continue;
    final id = tag[1].toLowerCase();
    if (!_hexId.hasMatch(id)) continue;
    if (seen.add(id)) ids.add(id);
    if (ids.length == maxPinnedNotes) break;
  }
  return ids;
}

/// Keeps only notes and polls that [owner] wrote, in the order of
/// [orderedIds]. Ids with no matching event are dropped.
List<NostrEvent> orderPinned({
  required String owner,
  required List<String> orderedIds,
  required Iterable<NostrEvent> events,
}) {
  final author = owner.toLowerCase();
  final byId = <String, NostrEvent>{};
  for (final event in events) {
    if (event.pubkey == author && (event.kind == 1 || event.kind == 1068)) {
      byId[event.id] = event;
    }
  }
  return [
    for (final id in orderedIds)
      if (byId[id] != null) byId[id]!,
  ];
}

/// Fetches the notes [pubkey] has pinned. Returns null when no relay
/// answered, and an empty list when the user has no pins.
Future<List<NostrEvent>?> fetchPinnedNotes({
  required RelayService relayService,
  required String pubkey,
  required List<String> relays,
}) async {
  final owner = pubkey.toLowerCase();

  final lists = await relayService.queryEvents(
    {
      'kinds': [kPinListKind],
      'authors': [owner],
      'limit': 5,
    },
    relays,
  );
  if (!lists.reachedRelay) return null;

  final own = lists.events
      .where((event) => event.kind == kPinListKind && event.pubkey == owner)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  if (own.isEmpty) return const [];

  final ids = pinnedIdsFromList(own.first);
  if (ids.isEmpty) return const [];

  final notes = await relayService.queryEvents({'ids': ids}, relays);
  return orderPinned(owner: owner, orderedIds: ids, events: notes.events);
}
