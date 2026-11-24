import 'nostr_event.dart';

class PollResults {
  const PollResults({
    required this.optionCounts,
    required this.voterCount,
    required this.myResponses,
  });

  /// option code -> number of voters who chose it.
  final Map<String, int> optionCounts;

  /// Number of distinct authors whose latest response had at least one option.
  final int voterCount;

  /// The current user's latest chosen option codes (empty if not voted).
  final List<String> myResponses;
}

/// Tallies already-verified kind 1018 events.
///
/// Counting rules (explicit, and only as good as your selected relays):
/// 1. Only kind 1018 events referencing [pollId] with an `e` tag are counted.
/// 2. Per author, only the newest event wins (re-voting replaces the old one).
/// 3. Each `response` tag that matches an option code of the poll counts once.
PollResults buildPollResults({
  required String pollId,
  required Iterable<NostrEvent> verifiedEvents,
  String? myPubkey,
}) {
  final byAuthor = <String, NostrEvent>{};

  for (final event in verifiedEvents) {
    if (event.kind != 1018) continue;
    final referencesPoll = event.tags.any(
      (tag) => tag.length >= 2 && tag[0] == 'e' && tag[1] == pollId,
    );
    if (!referencesPoll) continue;

    final existing = byAuthor[event.pubkey];
    if (existing == null || event.createdAt > existing.createdAt) {
      byAuthor[event.pubkey] = event;
    }
  }

  final counts = <String, int>{};
  var voters = 0;
  var myResponses = <String>[];

  for (final event in byAuthor.values) {
    final codes = [
      for (final tag in event.tags)
        if (tag.length >= 2 && tag[0] == 'response') tag[1],
    ];
    if (codes.isEmpty) continue;
    voters++;
    for (final code in codes.toSet()) {
      counts[code] = (counts[code] ?? 0) + 1;
    }
    if (myPubkey != null && event.pubkey == myPubkey) {
      myResponses = codes;
    }
  }

  return PollResults(
    optionCounts: counts,
    voterCount: voters,
    myResponses: myResponses,
  );
}
