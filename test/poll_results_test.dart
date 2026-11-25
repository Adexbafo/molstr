import 'package:flutter_test/flutter_test.dart';
import 'package:molstr/core/nostr/nostr_event.dart';
import 'package:molstr/core/nostr/poll_results.dart';

void main() {
  NostrEvent vote(
    String keyByte,
    String pollId,
    List<String> responses,
    int createdAt,
  ) {
    return NostrEvent.sign(
      privateKeyHex: List.filled(32, keyByte).join(),
      kind: 1018,
      content: '',
      createdAt: createdAt,
      tags: [
        ['e', pollId],
        for (final r in responses) ['response', r],
      ],
    );
  }

  test('latest response per author wins (re-voting replaces)', () {
    final pollId = List.filled(32, 'aa').join();
    final oldVote = vote('11', pollId, ['0'], 1700000000);
    final updatedVote = vote('11', pollId, ['1'], 1700000100);
    final otherVote = vote('22', pollId, ['0'], 1700000200);

    final results = buildPollResults(
      pollId: pollId,
      verifiedEvents: [oldVote, updatedVote, otherVote],
      myPubkey: oldVote.pubkey,
    );

    expect(results.voterCount, 2);
    expect(results.optionCounts['0'], 1);
    expect(results.optionCounts['1'], 1);
    expect(results.voters.length, 2);
  });

  test('multiplechoice response tags are all counted', () {
    final pollId = List.filled(32, 'bb').join();
    final multi = vote('11', pollId, ['0', '1'], 1700000000);

    final results = buildPollResults(
      pollId: pollId,
      verifiedEvents: [multi],
      myPubkey: multi.pubkey,
    );

    expect(results.voterCount, 1);
    expect(results.optionCounts['0'], 1);
    expect(results.optionCounts['1'], 1);
    expect(results.myResponses, containsAll(['0', '1']));
  });

  test('events not referencing the poll are ignored', () {
    final pollId = List.filled(32, 'cc').join();
    final unrelated = NostrEvent.sign(
      privateKeyHex: List.filled(32, '33').join(),
      kind: 1018,
      content: '',
      createdAt: 1700000000,
      tags: [
        ['e', List.filled(32, '99').join()],
        ['response', '0'],
      ],
    );

    final results = buildPollResults(
      pollId: pollId,
      verifiedEvents: [unrelated],
    );

    expect(results.voterCount, 0);
    expect(results.optionCounts, isEmpty);
  });

  test('non-1018 events are ignored', () {
    final pollId = List.filled(32, 'dd').join();
    final reply = NostrEvent.sign(
      privateKeyHex: List.filled(32, '44').join(),
      kind: 1,
      content: 'looks good',
      createdAt: 1700000000,
      tags: [
        ['e', pollId],
        ['response', '0'],
      ],
    );

    final results = buildPollResults(
      pollId: pollId,
      verifiedEvents: [reply],
    );

    expect(results.voterCount, 0);
  });
}
