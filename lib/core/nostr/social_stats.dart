import 'relay_service.dart';

class SocialStats {
  const SocialStats({this.following, this.followers});

  /// Null means unavailable, which must not be displayed as zero.
  final int? following;
  final int? followers;
}

Future<SocialStats> loadSocialStats({
  required RelayService relayService,
  required String pubkey,
  required List<String> relays,
}) async {
  final mine = await relayService.queryEvents(
    {
      'kinds': [3],
      'authors': [pubkey],
      'limit': 5,
    },
    relays,
  );

  int? following;
  if (mine.reachedRelay) {
    if (mine.events.isEmpty) {
      following = 0;
    } else {
      mine.events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      following = mine.events.first.tags
          .where((tag) => tag.length >= 2 && tag[0] == 'p')
          .length;
    }
  }

  final referenced = await relayService.queryEvents(
    {
      'kinds': [3],
      '#p': [pubkey],
      'limit': 100,
    },
    relays,
  );

  int? followers;
  if (referenced.reachedRelay) {
    final authors = referenced.events.map((event) => event.pubkey).toSet();
    if (authors.isEmpty) {
      followers = 0;
    } else {
      final latest = await relayService.queryEvents(
        {
          'kinds': [3],
          'authors': authors.take(80).toList(),
          'limit': 200,
        },
        relays,
      );
      final newest = <String, dynamic>{};
      for (final event in latest.events) {
        final existing = newest[event.pubkey];
        if (existing == null || event.createdAt > existing.createdAt) {
          newest[event.pubkey] = event;
        }
      }
      followers = authors.where((author) {
        final event = newest[author];
        if (event == null) return false;
        return event.tags.any(
          (tag) =>
              tag.length >= 2 &&
              tag[0] == 'p' &&
              tag[1].toLowerCase() == pubkey.toLowerCase(),
        );
      }).length;
    }
  }

  return SocialStats(following: following, followers: followers);
}
