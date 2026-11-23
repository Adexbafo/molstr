import 'nostr_event.dart';

class NoteEngagement {
  const NoteEngagement({
    required this.replies,
    required this.likes,
    required this.reposts,
  });

  final int replies;
  final int likes;
  final int reposts;
}

/// [verifiedEvents] must contain events whose IDs and signatures have
/// already been checked. Counts are observations, not global totals.
Map<String, NoteEngagement> tallyNoteEngagement({
  required Iterable<String> noteIds,
  required Iterable<NostrEvent> verifiedEvents,
}) {
  final ids = noteIds.toSet();

  final replyIds = <String, Set<String>>{
    for (final id in ids) id: <String>{},
  };
  final likeAuthors = <String, Set<String>>{
    for (final id in ids) id: <String>{},
  };
  final repostAuthors = <String, Set<String>>{
    for (final id in ids) id: <String>{},
  };

  final seenEvents = <String>{};

  for (final event in verifiedEvents) {
    // One event delivered by two relays is still one interaction.
    if (!seenEvents.add(event.id)) continue;

    if (event.kind == 1) {
      final parentId = _directReplyTarget(event.tags);
      if (parentId != null && ids.contains(parentId)) {
        replyIds[parentId]!.add(event.id);
      }
    } else if (event.kind == 7) {
      // Count likes, not dislikes or arbitrary emoji reactions.
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
    }
  }

  return {
    for (final id in ids)
      id: NoteEngagement(
        replies: replyIds[id]!.length,
        likes: likeAuthors[id]!.length,
        reposts: repostAuthors[id]!.length,
      ),
  };
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

  // A marked reply takes precedence over a root reference.
  for (final tag in references.reversed) {
    if (tag.length >= 4 && tag[3] == 'reply') return tag[1];
  }

  // Legacy, unmarked references: the last one is the parent.
  for (final tag in references.reversed) {
    if (tag.length < 4 || tag[3].isEmpty) return tag[1];
  }

  // MolStr's direct replies to root notes have one root-marked reference.
  if (references.length == 1 &&
      references.single.length >= 4 &&
      references.single[3] == 'root') {
    return references.single[1];
  }

  return null;
}
