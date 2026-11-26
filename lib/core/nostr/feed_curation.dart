import 'nostr_event.dart';
import 'relay_service.dart';

final _pubkeyPattern = RegExp(r'^[0-9a-f]{64}$');

/// Null means no matching list was observed. An empty list means a
/// matching kind-3 event was found but contained no valid follows.
List<String>? latestFollowKeys(
  Iterable<NostrEvent> verifiedEvents,
  String author,
) {
  NostrEvent? latest;
  for (final event in verifiedEvents) {
    if (event.kind != 3 || event.pubkey != author) continue;

    if (latest == null ||
        event.createdAt > latest.createdAt ||
        (event.createdAt == latest.createdAt &&
            event.id.compareTo(latest.id) < 0)) {
      latest = event;
    }
  }

  if (latest == null) return null;

  return <String>{
    for (final tag in latest.tags)
      if (tag.length >= 2 &&
          tag[0] == 'p' &&
          tag[1].length == 64 &&
          _pubkeyPattern.hasMatch(tag[1]))
        tag[1],
  }.toList(growable: false);
}

List<String> _expansionAuthors(String viewer, List<String> follows) =>
    follows.where((key) => key != viewer).toSet().take(20).toList();

Set<String> buildTrustSet({
  required String viewer,
  required List<String> follows,
  required Iterable<NostrEvent> verifiedLists,
}) {
  final trusted = <String>{viewer, ...follows};
  var remaining = 2000;

  for (final author in _expansionAuthors(viewer, follows)) {
    final keys = latestFollowKeys(verifiedLists, author) ?? const <String>[];
    for (final key in keys) {
      if (trusted.add(key)) {
        remaining--;
        if (remaining == 0) return trusted;
      }
    }
  }

  return trusted;
}

Future<Set<String>?> loadTrustSet({
  required RelayService relayService,
  required String viewer,
  required List<String> relays,
}) async {
  if (relays.isEmpty) return null;

  final ownList = await relayService.queryEvents(
    {
      'kinds': [3],
      'authors': [viewer],
      'limit': 1,
    },
    relays,
  );

  final follows = latestFollowKeys(ownList.events, viewer);
  if (follows == null) return null;

  final authors = _expansionAuthors(viewer, follows);
  var verifiedLists = const <NostrEvent>[];

  if (authors.isNotEmpty) {
    try {
      final query = await relayService.queryEvents(
        {
          'kinds': [3],
          'authors': authors,
          'limit': 40,
        },
        relays,
      );
      verifiedLists = query.events;
    } catch (_) {
      // Keep direct follows usable if second-hop lookup fails.
    }
  }

  return buildTrustSet(
    viewer: viewer,
    follows: follows,
    verifiedLists: verifiedLists,
  );
}

List<NostrEvent> collapseRepeatedNotes(Iterable<NostrEvent> notes) {
  final newestFirst = notes.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final seen = <(String, String)>{};

  return [
    for (final note in newestFirst)
      if (seen.add((note.pubkey, note.content.trim()))) note,
  ];
}
