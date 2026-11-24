import 'package:shared_preferences/shared_preferences.dart';

import 'identity_service.dart';
import 'relay_service.dart';

class FollowService {
  FollowService({
    required this.identityService,
    required this.relayService,
    required this.preferences,
  });

  final IdentityService identityService;
  final RelayService relayService;
  final SharedPreferences preferences;

  static const _followsKey = 'molstr.follows.v1.';

  Set<String> _cached(String me) =>
      (preferences.getStringList('$_followsKey$me') ?? []).toSet();

  Future<void> _cache(String me, Set<String> follows) =>
      preferences.setStringList('$_followsKey$me', follows.toList());

  bool isFollowing(String me, String target) =>
      _cached(me).contains(target.toLowerCase());

  /// Replaces the cache with the newest verified kind-3 from relays.
  Future<Set<String>> syncFollows(String me, List<String> relays) async {
    final events = await relayService.fetchEvents(
      {
        'kinds': [3],
        'authors': [me],
        'limit': 5,
      },
      relays,
    );
    if (events.isNotEmpty) {
      events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final follows = <String>{
        for (final tag in events.first.tags)
          if (tag.length >= 2 && tag[0] == 'p') tag[1].toLowerCase(),
      };
      await _cache(me, follows);
      return follows;
    }
    // No contact list on your relays yet — keep (possibly empty) cache.
    return _cached(me);
  }

  Future<bool> setFollow({
    required String target,
    required bool follow,
    required List<String> relays,
  }) async {
    final me = await identityService.currentIdentity();
    if (me == null) return false;

    // Merge against relays, never against a local cache alone.
    final current = await syncFollows(me.pubkey, relays);
    final hints = <String, String>{};
    final latest = await relayService.fetchEvents(
      {
        'kinds': [3],
        'authors': [me.pubkey],
        'limit': 1,
      },
      relays,
    );
    for (final event in latest) {
      for (final tag in event.tags) {
        if (tag.length >= 2 && tag[0] == 'p') {
          hints[tag[1].toLowerCase()] = tag.length >= 3 ? tag[2] : '';
        }
      }
    }

    final next = Set<String>.from(current);
    final t = target.toLowerCase();
    if (follow) {
      next.add(t);
    } else {
      next.remove(t);
    }

    final event = await identityService.signEvent(
      kind: 3,
      content: '',
      tags: next.map((pk) => ['p', pk, hints[pk] ?? '']).toList(),
    );
    final result = await relayService.publishEvent(event, relays);
    final ok = result.values.where((v) => v == 'ok').length;
    if (ok > 0) await _cache(me.pubkey, next);
    return ok > 0;
  }
}
