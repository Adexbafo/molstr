import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/nostr/follow_service.dart';
import '../../core/nostr/identity_service.dart';
import '../../core/nostr/interactions.dart';
import '../../core/nostr/nip19.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/relay_service.dart';
import '../../ui/render/note_card.dart';
import '../../ui/widgets/molstr_avatar.dart';
import '../../ui/widgets/nip05_badge.dart';

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
  late final FollowService _followService;

  FeedResult? _result;
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
    final result = await widget.interactions.relayService.fetchFeed(
      widget.interactions.relays,
      limit: 30,
      authors: [widget.pubkey],
    );
    var following = _following;
    if (me != null && me.pubkey != widget.pubkey) {
      await _followService.syncFollows(
        me.pubkey,
        widget.interactions.relays,
      );
      following = _followService.isFollowing(me.pubkey, widget.pubkey);
    }
    if (!mounted) return;
    setState(() {
      _me = me;
      _result = result;
      _following = following;
      _loading = false;
    });
  }

  Future<void> _toggleFollow() async {
    if (_followBusy || _me == null) {
      if (_me == null) _message('Connect a key in Profile to follow.');
      return;
    }
    setState(() => _followBusy = true);
    final ok = await _followService.setFollow(
      target: widget.pubkey,
      follow: !_following,
      relays: widget.interactions.relays,
    );
    if (!mounted) return;
    setState(() {
      _followBusy = false;
      if (ok) _following = !_following;
    });
    _message(ok
        ? (_following ? 'Following.' : 'Unfollowed.')
        : 'No relay accepted the change.');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final profile = _result?.profiles[widget.pubkey];
    final bestName = profile?.bestName ?? shortNpub(_npub);
    final notes = _result?.notes ?? const <NostrEvent>[];
    final isOwn = _me?.pubkey == widget.pubkey;

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
                  child: SizedBox(
                    width: double.infinity,
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
                                onPressed: _followBusy ? null : _toggleFollow,
                                icon: const Icon(Icons.check),
                                label: Text(
                                  _followBusy
                                      ? 'Updating…'
                                      : 'Following · tap to unfollow',
                                ),
                              )
                            : FilledButton.icon(
                                onPressed: _followBusy ? null : _toggleFollow,
                                icon: _followBusy
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.person_add),
                                label: const Text('Follow'),
                              ),
                  ),
                ),
              const Divider(),
              if (_loading && _result == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (notes.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No notes found on your relays for this user yet.',
                  ),
                )
              else
                for (final note in notes)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: NoteCard(
                      event: note,
                      profile: _result?.profiles[note.pubkey],
                      provenance: relayProvenance(_result?.noteRelays[note.id]),
                      loadImages: widget.loadImages,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
