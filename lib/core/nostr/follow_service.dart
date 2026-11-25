import 'package:shared_preferences/shared_preferences.dart';

import 'identity_service.dart';
import 'relay_service.dart';

enum FollowUpdateResult { published, noIdentity, unknownState, rejected }

class FollowService {
  FollowService({
    required this.identityService,
    required this.relayService,
    required this.preferences,
  });

  final IdentityService identityService;
  final RelayService relayService;
  final SharedPreferences preferences;

  static const _followsKey = 'molstr.follows.v2.';

  Set<String> cachedFollows(String me) =>
      (preferences.getStringList('$_followsKey$me') ?? []).toSet();

  Future<void> _cache(String me, Set<String> follows) =>
      preferences.setStringList('$_followsKey$me', follows.toList());

  bool isFollowing(String me, String target) =>
      cachedFollows(me).contains(target.toLowerCase());

  /// Returns null when the follow list cannot be established:
  /// no relay answered, or none held a list while some relays were silent.
  Future<Set<String>?> syncFollows(String me, List<String> relays) async {
    final query = await relayService.queryEvents(
      {
        'kinds': [3],
        'authors': [me],
        'limit': 5,
      },
      relays,
    );

    if (!query.reachedRelay) return null;

    if (query.events.isEmpty) {
      // Only treat "no list" as empty when every relay answered.
      if (query.respondingRelays < relays.length) return null;
      await _cache(me, <String>{});
      return <String>{};
    }

    query.events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final follows = <String>{
      for (final tag in query.events.first.tags)
        if (tag.length >= 2 && tag[0] == 'p') tag[1].toLowerCase(),
    };
    await _cache(me, follows);
    return follows;
  }

  Future<FollowUpdateResult> setFollow({
    required String target,
    required bool follow,
    required List<String> relays,
  }) async {
    final me = await identityService.currentIdentity();
    if (me == null) return FollowUpdateResult.noIdentity;

    final current = await syncFollows(me.pubkey, relays);
    if (current == null) return FollowUpdateResult.unknownState;

    final hints = <String, String>{};
    final latest = await relayService.queryEvents(
      {
        'kinds': [3],
        'authors': [me.pubkey],
        'limit': 1,
      },
      relays,
    );
    for (final event in latest.events) {
      for (final tag in event.tags) {
        if (tag.length >= 2 && tag[0] == 'p') {
          hints[tag[1].toLowerCase()] = tag.length >= 3 ? tag[2] : '';
        }
      }
    }

    final next = Set<String>.from(current);
    final targetKey = target.toLowerCase();
    if (follow) {
      next.add(targetKey);
    } else {
      next.remove(targetKey);
    }

    final event = await identityService.signEvent(
      kind: 3,
      content: '',
      tags: [
        for (final pk in next) ['p', pk, hints[pk] ?? ''],
      ],
    );

    final results = await relayService.publishEvent(event, relays);
    final ok = results.values.where((value) => value == 'ok').length;
    if (ok == 0) return FollowUpdateResult.rejected;

    await _cache(me.pubkey, next);
    return FollowUpdateResult.published;
  }
}
