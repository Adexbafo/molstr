import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../text/hashtags.dart';
import 'identity_service.dart';
import 'nip19.dart';
import 'nostr_event.dart';
import 'relay_service.dart';

class Interactions {
  Interactions({
    required this.identityService,
    required this.relayService,
    required this.relays,
    required this.preferences,
    required this.canSign,
  });

  final IdentityService identityService;
  final RelayService relayService;
  final List<String> relays;
  final SharedPreferences preferences;
  final bool canSign;

  static const likedKey = 'interactions.liked';
  static const repostedKey = 'interactions.reposted';

  bool isLiked(String id) => _list(likedKey).contains(id);
  bool isReposted(String id) => _list(repostedKey).contains(id);

  List<String> _list(String key) => preferences.getStringList(key) ?? const [];

  Future<void> _remember(String key, String id) async {
    final next = [..._list(key).where((e) => e != id), id];
    final trimmed =
        next.length > 2000 ? next.sublist(next.length - 2000) : next;
    await preferences.setStringList(key, trimmed);
  }

  Future<int> _publish(NostrEvent event) async {
    final results = await relayService.publishEvent(event, relays);
    return results.values.where((v) => v == 'ok').length;
  }

  /// NIP-25 reaction.
  Future<int> like(NostrEvent target) async {
    final event = await identityService.signEvent(
      kind: 7,
      content: '+',
      tags: [
        ['e', target.id],
        ['p', target.pubkey],
        ['k', '${target.kind}'],
      ],
    );
    final ok = await _publish(event);
    if (ok > 0) await _remember(likedKey, target.id);
    return ok;
  }

  /// NIP-18 repost: kind 6 for text notes, kind 16 for other kinds.
  Future<int> repost(NostrEvent target) async {
    final hint = relays.isNotEmpty ? relays.first : '';
    final isNote = target.kind == 1;
    final event = await identityService.signEvent(
      kind: isNote ? 6 : 16,
      content: jsonEncode(target.toJson()),
      tags: [
        ['e', target.id, hint],
        ['p', target.pubkey],
        if (!isNote) ['k', '${target.kind}'],
      ],
    );
    final ok = await _publish(event);
    if (ok > 0) await _remember(repostedKey, target.id);
    return ok;
  }

  /// NIP-18 quote note: kind 1 with a `q` tag and `nostr:note1...` reference.
  Future<int> quote(NostrEvent target, String commentary) async {
    final trimmed = commentary.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Enter text for your quote note.');
    }

    final noteRef = Nip19.encodeKey('note', target.id);
    final hint = relays.isNotEmpty ? relays.first : '';
    final event = await identityService.signEvent(
      kind: 1,
      content: '$trimmed\n\nnostr:$noteRef',
      tags: [
        ...quoteTags(target, relayHint: hint),
        ...Hashtags.extract(trimmed).map((t) => ['t', t]),
      ],
    );
    return _publish(event);
  }

  /// NIP-88 vote on a kind 1068 poll (kind 1018 response).
  ///
  /// One `response` tag is written per chosen option code.
  Future<int> votePoll(NostrEvent poll, List<String> responseCodes) async {
    if (responseCodes.isEmpty) {
      throw const FormatException('Select at least one option.');
    }
    final hint = relays.isNotEmpty ? relays.first : '';
    final event = await identityService.signEvent(
      kind: 1018,
      content: '',
      tags: [
        ['e', poll.id, hint],
        for (final code in responseCodes) ['response', code],
      ],
    );
    return _publish(event);
  }

  /// NIP-10 reply to a kind-1 note.
  Future<int> reply(NostrEvent parent, String content) async {
    final event = await identityService.signEvent(
      kind: 1,
      content: content,
      tags: [
        ...replyTags(parent),
        ...Hashtags.extract(content).map((t) => ['t', t]),
      ],
    );
    return _publish(event);
  }

  static List<List<String>> quoteTags(
    NostrEvent target, {
    String relayHint = '',
  }) {
    return [
      ['q', target.id, relayHint, target.pubkey],
      ['p', target.pubkey],
    ];
  }

  /// Builds NIP-10 marked e/p tags for replying to [parent].
  static List<List<String>> replyTags(NostrEvent parent) {
    String? rootId;
    for (final tag in parent.tags) {
      if (tag.length >= 4 && tag[0] == 'e' && tag[3] == 'root') {
        rootId = tag[1];
        break;
      }
    }

    final pubkeys = <String>{
      parent.pubkey,
      for (final tag in parent.tags)
        if (tag.length >= 2 && tag[0] == 'p') tag[1],
    };

    return [
      if (rootId != null) ...[
        ['e', rootId, '', 'root'],
        ['e', parent.id, '', 'reply'],
      ] else
        ['e', parent.id, '', 'root'],
      for (final p in pubkeys) ['p', p],
    ];
  }

  Future<void> clearLocalState() async {
    await preferences.remove(likedKey);
    await preferences.remove(repostedKey);
  }
}

/// Makes [Interactions] available to note cards anywhere below it.
class InteractionsScope extends InheritedWidget {
  const InteractionsScope({
    super.key,
    required this.interactions,
    required super.child,
  });

  final Interactions interactions;

  static Interactions? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<InteractionsScope>()
      ?.interactions;

  @override
  bool updateShouldNotify(InteractionsScope oldWidget) =>
      oldWidget.interactions != interactions;
}
