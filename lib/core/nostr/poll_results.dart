import 'nostr_event.dart';

class PollVoter {
  const PollVoter({
    required this.pubkey,
    required this.responses,
    required this.createdAt,
  });

  final String pubkey;
  final List<String> responses;
  final int createdAt;
}

class PollResults {
  const PollResults({
    required this.optionCounts,
    required this.voterCount,
    required this.myResponses,
    this.voters = const [],
    this.available = true,
  });

  final Map<String, int> optionCounts;
  final int voterCount;
  final List<String> myResponses;
  final List<PollVoter> voters;

  /// False means the relays could not be reached, not that nobody voted.
  final bool available;
}

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
  final voters = <PollVoter>[];
  var myResponses = <String>[];

  for (final event in byAuthor.values) {
    final codes = [
      for (final tag in event.tags)
        if (tag.length >= 2 && tag[0] == 'response') tag[1],
    ];
    if (codes.isEmpty) continue;

    for (final code in codes.toSet()) {
      counts[code] = (counts[code] ?? 0) + 1;
    }
    voters.add(
      PollVoter(
        pubkey: event.pubkey,
        responses: codes,
        createdAt: event.createdAt,
      ),
    );
    if (myPubkey != null && event.pubkey == myPubkey) {
      myResponses = codes;
    }
  }

  voters.sort((a, b) => b.createdAt.compareTo(a.createdAt));

  return PollResults(
    optionCounts: counts,
    voterCount: voters.length,
    myResponses: myResponses,
    voters: voters,
  );
}
