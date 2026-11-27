import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/nostr/follow_service.dart';
import '../../core/nostr/identity_service.dart';
import '../../core/nostr/interactions.dart';
import '../../core/nostr/nip19.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/note_engagement.dart';
import '../../core/nostr/pinned_notes.dart';
import '../../core/nostr/relay_service.dart';
import '../../core/nostr/user_relays.dart';
import '../../ui/render/note_card.dart';
import '../../ui/render/poll_card.dart';
import '../../ui/widgets/molstr_avatar.dart';
import '../../ui/widgets/nip05_badge.dart';
import '../../ui/widgets/social_counts_line.dart';
import '../messages/chat_page.dart';
import '../../ui/payments/zap_sheet.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({
    super.key,
    required this.pubkey,
    required this.interactions,
    required this.loadImages,
  });

  final String pubkey;
  final Interactions interactions;
  final bool loadImages;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  /// The relay layer accepts at most 60 ids per count request.
  static const _countBatchSize = 60;

  late final FollowService _followService;

  FeedResult? _result;
  List<NostrEvent> _pinned = const [];
  Map<String, NoteEngagement> _engagement = const {};
  int _engagementGeneration = 0;
  Identity? _me;
  bool _loading = true;
  bool _following = false;
  bool _followBusy = false;

  String get _npub => Nip19.npubFromHex(widget.pubkey);

  @override
  void initState() {
    super.initState();
    _followService = FollowService(
      identityService: widget.interactions.identityService,
      relayService: widget.interactions.relayService,
      preferences: widget.interactions.preferences,
    );
    _load();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final me = await widget.interactions.identityService.currentIdentity();

    final relayService = UserRelayService(
      relayService: widget.interactions.relayService,
      identityService: widget.interactions.identityService,
      preferences: widget.interactions.preferences,
    );

    final userList = await relayService.fetchRelayList(
      pubkey: widget.pubkey,
      selectedRelays: widget.interactions.relays,
    );

    final relaysForReading = <String>{
      ...widget.interactions.relays,
      if (userList != null) ...userList.relaysForReading(),
      ...relayService.loadGlobalRelays(),
    }.toList();

    final result = await widget.interactions.relayService.fetchFeed(
      relaysForReading,
      limit: 30,
      authors: [widget.pubkey],
    );

    // Pins live on the user's own write relays, so read from the wide set.
    // A failed lookup keeps whatever pins were last seen.
    List<NostrEvent>? pins;
    try {
      pins = await fetchPinnedNotes(
        relayService: widget.interactions.relayService,
        pubkey: widget.pubkey,
        relays: relaysForReading,
      );
    } catch (_) {
      pins = null;
    }

    var following = _following;
    if (me != null && me.pubkey != widget.pubkey) {
      final state = await _followService.syncFollows(
        me.pubkey,
        relaysForReading,
      );
      if (state != null) {
        following = state.contains(widget.pubkey.toLowerCase());
      }
    }

    if (!mounted) return;
    setState(() {
      _me = me;
      _result = result;
      _pinned = pins ?? _pinned;
      _engagement = const {};
      _following = following;
      _loading = false;
    });

    unawaited(_loadEngagement(result));
  }

  Future<void> _loadEngagement(FeedResult result) async {
    final generation = ++_engagementGeneration;

    final ids = <String>{
      for (final event in _pinned) event.id,
      for (final note in result.notes) note.id,
    }.toList();
    if (ids.isEmpty || result.connectedRelays.isEmpty) return;

    try {
      for (var start = 0; start < ids.length; start += _countBatchSize) {
        final next = start + _countBatchSize;
        final end = next < ids.length ? next : ids.length;

        final counts =
            await widget.interactions.relayService.fetchNoteEngagement(
          ids.sublist(start, end),
          widget.interactions.relays,
        );

        if (!mounted || generation != _engagementGeneration) return;
        setState(() => _engagement = {..._engagement, ...counts});
      }
    } catch (_) {
      // Counts are optional. The notes stay readable without them.
    }
  }

  Future<void> _toggleFollow() async {
    if (_followBusy) return;
    if (_me == null) {
      _message('Connect a key in Profile to follow.');
      return;
    }

    setState(() => _followBusy = true);
    final result = await _followService.setFollow(
      target: widget.pubkey,
      follow: !_following,
      relays: widget.interactions.relays,
    );
    if (!mounted) return;

    setState(() {
      _followBusy = false;
      if (result == FollowUpdateResult.published) {
        _following = !_following;
      }
    });

    switch (result) {
      case FollowUpdateResult.published:
        _message(_following ? 'Following.' : 'Unfollowed.');
      case FollowUpdateResult.noIdentity:
        _message('Connect a key in Profile to follow.');
      case FollowUpdateResult.unknownState:
        _message(
          'Some relays did not respond, so your follow list was not changed.',
        );
      case FollowUpdateResult.rejected:
        _message('No relay accepted the change.');
    }
  }

  Future<void> _zapProfile() async {
    final profile = _result?.profiles[widget.pubkey];
    final lud16 = profile?.lud16;

    if (_me == null) {
      _message('Connect a key in Profile to zap.');
      return;
    }
    if (lud16 == null || lud16.trim().isEmpty) {
      _message('This profile has no Lightning address.');
      return;
    }

    await showZapSheet(
      context: context,
      recipientName: profile?.bestName ?? shortNpub(_npub),
      recipientLud16: lud16.trim(),
      recipientPubkeyHex: widget.pubkey,
      noteEvent: null, // profile zap: no e tag
      relays: widget.interactions.relays,
      identityService: widget.interactions.identityService,
      relayService: widget.interactions.relayService,
    );
  }

  void _openChat() {
    final me = _me;
    if (me == null) {
      _message('Connect a key in Profile to send messages.');
      return;
    }
    Navigator.of(context)
        .push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(
          partnerPubkey: widget.pubkey.toLowerCase(),
          identityService: widget.interactions.identityService,
          relayService: widget.interactions.relayService,
          relays: widget.interactions.relays,
          loadImages: widget.loadImages,
          initialProfile: _result?.profiles[widget.pubkey],
        ),
      ),
    )
        .then((_) {
      if (mounted) _load();
    });
  }

  /// A note or poll as a card. Pins can be either.
  Widget _card(NostrEvent event) {
    final result = _result;
    final profile = result?.profiles[event.pubkey];
    final provenance = relayProvenance(result?.noteRelays[event.id]);

    if (event.kind == 1068) {
      final poll = PollData.fromEvent(event);
      if (poll != null) {
        return PollCard(
          key: ValueKey('poll:${event.id}'),
          poll: poll,
          profile: profile,
          provenance: provenance,
          loadImages: widget.loadImages,
          engagement: _engagement[event.id],
        );
      }
    }
    return NoteCard(
      key: ValueKey('note:${event.id}'),
      event: event,
      profile: profile,
      provenance: provenance,
      loadImages: widget.loadImages,
      engagement: _engagement[event.id],
    );
  }

  Widget _sectionTitle(String text, {IconData? icon}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16),
            const SizedBox(width: 6),
          ],
          Text(text, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final profile = _result?.profiles[widget.pubkey];
    final bestName = profile?.bestName ?? shortNpub(_npub);
    final isOwn = _me?.pubkey == widget.pubkey;

    // Pinned notes move to their own section instead of appearing twice.
    final pinnedIds = {for (final event in _pinned) event.id};
    final notes = [
      for (final note in _result?.notes ?? const <NostrEvent>[])
        if (!pinnedIds.contains(note.id)) note,
    ];
    final hasAnything = notes.isNotEmpty || _pinned.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(bestName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Open profile on njump.me',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => launchUrl(
              Uri.parse('https://njump.me/$_npub'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: InteractionsScope(
        interactions: widget.interactions,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                height: 96,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF4C1D95)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MolStrAvatar(
                      name: bestName,
                      picture: profile?.picture,
                      loadImages: widget.loadImages,
                      radius: 40,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bestName,
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SelectableText(
                            shortNpub(_npub),
                            style: textTheme.bodySmall,
                          ),
                          if (profile?.nip05 != null)
                            Nip05Badge(
                              identifier: profile!.nip05!,
                              pubkey: widget.pubkey,
                            ),
                          const SizedBox(height: 6),
                          SocialCountsLine(
                            pubkey: widget.pubkey,
                            relayService: widget.interactions.relayService,
                            relays: widget.interactions.relays,
                          ),
                          if (profile?.about != null) ...[
                            const SizedBox(height: 8),
                            Text(profile!.about!),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!isOwn)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _me == null
                            ? OutlinedButton.icon(
                                onPressed: () => _message(
                                  'Connect a key in Profile to follow.',
                                ),
                                icon: const Icon(Icons.key_outlined),
                                label: const Text('Connect a key to follow'),
                              )
                            : _following
                                ? OutlinedButton.icon(
                                    onPressed:
                                        _followBusy ? null : _toggleFollow,
                                    icon: const Icon(Icons.check),
                                    label: Text(
                                      _followBusy
                                          ? 'Updating…'
                                          : 'Following · tap to unfollow',
                                    ),
                                  )
                                : FilledButton.icon(
                                    onPressed:
                                        _followBusy ? null : _toggleFollow,
                                    icon: _followBusy
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.person_add),
                                    label: const Text('Follow'),
                                  ),
                      ),
                      if (_me != null) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _openChat,
                          icon: const Icon(Icons.mail_outline),
                          label: const Text('Message'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _zapProfile,
                          icon: const Icon(Icons.bolt),
                          label: const Text('Zap'),
                        ),
                      ],
                    ],
                  ),
                ),
              const Divider(),
              if (_loading && _result == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (!hasAnything)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No notes found on your relays for this user yet.',
                  ),
                )
              else ...[
                if (_pinned.isNotEmpty) ...[
                  _sectionTitle('Pinned', icon: Icons.push_pin),
                  for (final event in _pinned)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _card(event),
                    ),
                  if (notes.isNotEmpty) _sectionTitle('Notes'),
                ],
                for (final note in notes)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _card(note),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
