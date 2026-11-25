import '../payments/zap_receipt.dart';
import 'nostr_event.dart';

class NoteEngagement {
  const NoteEngagement({
    required this.replies,
    required this.likes,
    required this.reposts,
    this.quotes = 0,
    this.zapSats = 0,
  });

  final int replies;
  final int likes;
  final int reposts;
  final int quotes;
  final int zapSats;
}

class NoteInteractions {
  const NoteInteractions({
    required this.replies,
    required this.quotes,
    required this.likes,
    required this.reposts,
    this.zaps = const [],
    required this.profiles,
    required this.eventRelays,
    required this.connectedRelays,
    required this.failedRelays,
  });

  final List<NostrEvent> replies;
  final List<NostrEvent> quotes;
  final List<NostrEvent> likes;
  final List<NostrEvent> reposts;
  final List<NostrEvent> zaps;
  final Map<String, ProfileMetadata> profiles;
  final Map<String, Set<String>> eventRelays;
  final List<String> connectedRelays;
  final List<String> failedRelays;

  int get totalZapSats => zaps.fold(
        0,
        (sum, event) => sum + (parseZapReceiptAmountMsats(event) ~/ 1000),
      );
}

int parseZapReceiptAmountMsats(NostrEvent event) {
  return validateZapReceipt(event)?.amountMsats ?? 0;
}

String formatSats(int sats) {
  if (sats >= 1000000) {
    final m = (sats / 1000000).toStringAsFixed(1);
    return '${m.endsWith('.0') ? m.substring(0, m.length - 2) : m}M';
  }
  if (sats >= 1000) {
    final k = (sats / 1000).toStringAsFixed(1);
    return '${k.endsWith('.0') ? k.substring(0, k.length - 2) : k}k';
  }
  return '$sats';
}

Map<String, NoteEngagement> tallyNoteEngagement({
  required Iterable<String> noteIds,
  required Iterable<NostrEvent> verifiedEvents,
}) {
  final ids = noteIds.toSet();

  final replyIds = <String, Set<String>>{
    for (final id in ids) id: <String>{},
  };
  final quoteIds = <String, Set<String>>{
    for (final id in ids) id: <String>{},
  };
  final likeAuthors = <String, Set<String>>{
    for (final id in ids) id: <String>{},
  };
  final repostAuthors = <String, Set<String>>{
    for (final id in ids) id: <String>{},
  };
  final zapReceipts = <String, Set<String>>{
    for (final id in ids) id: <String>{},
  };
  final zapSatsTotal = <String, int>{
    for (final id in ids) id: 0,
  };

  final seenEvents = <String>{};

  for (final event in verifiedEvents) {
    if (!seenEvents.add(event.id)) continue;

    if (event.kind == 1) {
      for (final tag in event.tags) {
        if (tag.length >= 2 && tag[0] == 'q' && ids.contains(tag[1])) {
          quoteIds[tag[1]]!.add(event.id);
        }
      }

      final parentId = _directReplyTarget(event.tags);
      if (parentId != null && ids.contains(parentId)) {
        replyIds[parentId]!.add(event.id);
      }
    } else if (event.kind == 7) {
      if (event.content != '+' && event.content != '❤️') continue;
      final targetId = _lastEventReference(event.tags);
      if (targetId != null && ids.contains(targetId)) {
        likeAuthors[targetId]!.add(event.pubkey);
      }
    } else if (event.kind == 6) {
      final targetId = _lastEventReference(event.tags);
      if (targetId != null && ids.contains(targetId)) {
        repostAuthors[targetId]!.add(event.pubkey);
      }
    } else if (event.kind == 9735) {
      final zap = validateZapReceipt(event);
      final target = zap?.eventId;
      if (target != null && ids.contains(target)) {
        if (zapReceipts[target]!.add(event.id)) {
          zapSatsTotal[target] =
              zapSatsTotal[target]! + (zap!.amountMsats ~/ 1000);
        }
      }
    }
  }

  return {
    for (final id in ids)
      id: NoteEngagement(
        replies: replyIds[id]!.length,
        likes: likeAuthors[id]!.length,
        reposts: repostAuthors[id]!.length,
        quotes: quoteIds[id]!.length,
        zapSats: zapSatsTotal[id]!,
      ),
  };
}

NoteInteractions buildNoteInteractions({
  required String targetId,
  required Iterable<NostrEvent> verifiedEvents,
  required Map<String, ProfileMetadata> profiles,
  required Map<String, Set<String>> eventRelays,
  required List<String> connectedRelays,
  required List<String> failedRelays,
}) {
  final repliesById = <String, NostrEvent>{};
  final quotesById = <String, NostrEvent>{};
  final likesByAuthor = <String, NostrEvent>{};
  final repostsByAuthor = <String, NostrEvent>{};
  final zapsById = <String, NostrEvent>{};
  final seenEvents = <String>{};

  for (final event in verifiedEvents) {
    if (!seenEvents.add(event.id)) continue;

    if (event.kind == 1) {
      final isQuote = event.tags.any(
        (tag) => tag.length >= 2 && tag[0] == 'q' && tag[1] == targetId,
      );
      if (isQuote) {
        quotesById.putIfAbsent(event.id, () => event);
      }

      final referencesEvent = event.tags.any(
        (tag) => tag.length >= 2 && tag[0] == 'e' && tag[1] == targetId,
      );
      if (referencesEvent) {
        repliesById.putIfAbsent(event.id, () => event);
      }
    } else if (event.kind == 7) {
      if (event.content != '+' && event.content != '❤️') continue;
      if (_lastEventReference(event.tags) != targetId) continue;

      final existing = likesByAuthor[event.pubkey];
      if (existing == null || event.createdAt > existing.createdAt) {
        likesByAuthor[event.pubkey] = event;
      }
    } else if (event.kind == 6) {
      if (_lastEventReference(event.tags) != targetId) continue;

      final existing = repostsByAuthor[event.pubkey];
      if (existing == null || event.createdAt > existing.createdAt) {
        repostsByAuthor[event.pubkey] = event;
      }
    } else if (event.kind == 9735) {
      final zap = validateZapReceipt(event);
      if (zap?.eventId == targetId) {
        zapsById.putIfAbsent(event.id, () => event);
      }
    }
  }

  final replies = repliesById.values.toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final quotes = quotesById.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final likes = likesByAuthor.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final reposts = repostsByAuthor.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final zaps = zapsById.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  return NoteInteractions(
    replies: replies,
    quotes: quotes,
    likes: likes,
    reposts: reposts,
    zaps: zaps,
    profiles: profiles,
    eventRelays: eventRelays,
    connectedRelays: connectedRelays,
    failedRelays: failedRelays,
  );
}

String? _lastEventReference(List<List<String>> tags) {
  for (final tag in tags.reversed) {
    if (tag.length >= 2 && tag[0] == 'e') return tag[1];
  }
  return null;
}

String? _directReplyTarget(List<List<String>> tags) {
  final references =
      tags.where((tag) => tag.length >= 2 && tag[0] == 'e').toList();

  for (final tag in references.reversed) {
    if (tag.length >= 4 && tag[3] == 'reply') return tag[1];
  }

  for (final tag in references.reversed) {
    if (tag.length < 4 || tag[3].isEmpty) return tag[1];
  }

  if (references.length == 1 &&
      references.single.length >= 4 &&
      references.single[3] == 'root') {
    return references.single[1];
  }

  return null;
}
