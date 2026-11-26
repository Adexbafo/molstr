import 'dart:async';
import '../../core/nostr/note_engagement.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/nostr/identity_service.dart';
import '../../core/nostr/relay_service.dart';
import '../../ui/render/note_card.dart';
import '../../ui/widgets/molstr_avatar.dart';
import '../../ui/widgets/nip05_badge.dart';
import '../../ui/widgets/social_counts_line.dart';
import 'profile_editor_page.dart';
import '../../core/nostr/nostr_event.dart';
import '../../ui/render/poll_card.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../ui/widgets/account_switcher_sheet.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.identity,
    required this.relayService,
    required this.relays,
    required this.loadImages,
    required this.identityService,
    required this.onOpenSupport,
    required this.onRemoveIdentity,
    required this.onAccountsChanged,
  });

  final Identity identity;
  final IdentityService identityService;
  final RelayService relayService;
  final List<String> relays;
  final bool loadImages;
  final VoidCallback onOpenSupport;
  final VoidCallback onRemoveIdentity;
  final VoidCallback onAccountsChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  FeedResult? _result;
  Map<String, NoteEngagement> _engagement = const {};
  int _engagementGeneration = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await widget.relayService.fetchFeed(
        widget.relays,
        limit: 50,
        authors: [widget.identity.pubkey],
      );

      if (!mounted) return;

      setState(() {
        _result = result;
        _engagement = const {};
        _loading = false;
      });

      unawaited(_loadEngagement(result));

      unawaited(_loadEngagement(result));
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Could not load your profile from your relays.';
      });
    }
  }

  Future<void> _loadEngagement(FeedResult result) async {
    final generation = ++_engagementGeneration;

    final ids = <String>{
      ...result.polls.map((poll) => poll.id),
      ...result.notes.map((note) => note.id),
    }.toList();

    if (ids.isEmpty || result.connectedRelays.isEmpty) return;

    try {
      // Ask every selected relay, not only those that answered this load.
      final counts = await widget.relayService.fetchNoteEngagement(
        ids,
        widget.relays,
      );

      if (!mounted || generation != _engagementGeneration) return;

      setState(() => _engagement = counts);
    } catch (_) {
      if (!mounted || generation != _engagementGeneration) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Interaction counts could not be refreshed. Try refreshing again.',
          ),
        ),
      );
    }
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
  }

  List<Widget> _notesTab(List<dynamic> notes) {
    if (notes.isEmpty) {
      return const [
        Center(
            child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
              'No notes from this identity were found on your relays yet.'),
        )),
      ];
    }
    final result = _result!;
    return notes.map((note) {
      return NoteCard(
          event: note,
          profile: result.profiles[note.pubkey],
          provenance: relayProvenance(result.noteRelays[note.id]),
          loadImages: widget.loadImages,
          engagement: _engagement[note.id]);
    }).toList();
  }

  List<Widget> _pollCards() {
    final result = _result;
    if (result == null) return const [];
    final parsed =
        result.polls.map(PollData.fromEvent).whereType<PollData>().toList();
    if (parsed.isEmpty) {
      return const [
        Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('No polls found on your relays yet.'),
          ),
        ),
      ];
    }
    return parsed
        .map(
          (poll) => PollCard(
            poll: poll,
            profile: result.profiles[poll.event.pubkey],
            provenance: relayProvenance(
              result.noteRelays[poll.event.id],
            ),
            loadImages: widget.loadImages,
            engagement: _engagement[poll.event.id],
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final profile = _result?.profiles[widget.identity.pubkey];
    final lud16 = profile?.lud16;
    final moneroAddress = profile?.moneroAddress;
    final name = profile?.bestName ?? shortNpub(widget.identity.npub);
    final picture = profile?.picture;
    final banner = profile?.banner;

    if (_loading && _result == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _result == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 56),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final notes =
        (_result?.notes ?? const []).where((n) => !n.isReply).toList();
    final replies =
        (_result?.notes ?? const []).where((n) => n.isReply).toList();
    final pollCount = (_result?.polls ?? const []).length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            SizedBox(
              height: banner != null &&
                      widget.loadImages &&
                      banner.startsWith('https://')
                  ? 110
                  : 72,
              width: double.infinity,
              child: banner != null &&
                      widget.loadImages &&
                      banner.startsWith('https://')
                  ? Image.network(banner,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _bannerGradient())
                  : _bannerGradient(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MolStrAvatar(
                    name: name,
                    picture: picture,
                    loadImages: widget.loadImages,
                    radius: 40,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        InkWell(
                          onTap: () =>
                              _copy(widget.identity.npub, 'npub copied.'),
                          child: Text(shortNpub(widget.identity.npub),
                              style: textTheme.bodySmall),
                        ),
                        if (profile?.nip05 != null) ...[
                          const SizedBox(height: 4),
                          Nip05Badge(
                            identifier: profile!.nip05!,
                            pubkey: widget.identity.pubkey,
                          ),
                        ],
                        const SizedBox(height: 6),
                        SocialCountsLine(
                          pubkey: widget.identity.pubkey,
                          relayService: widget.relayService,
                          relays: widget.relays,
                        ),
                        if (profile?.about != null) ...[
                          const SizedBox(height: 8),
                          Text(profile!.about!),
                        ],
                        if (lud16 != null) ...[
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () =>
                                _copy(lud16, 'Lightning address copied.'),
                            child: Row(children: [
                              const Icon(Icons.bolt, size: 16),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  lud16,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ]),
                          ),
                        ],
                        if (moneroAddress != null) ...[
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () =>
                                _copy(moneroAddress, 'Monero address copied.'),
                            child: Row(children: [
                              const Icon(Icons.lock_outline, size: 16),
                              const SizedBox(width: 4),
                              Flexible(
                                  child: Text(moneroAddress,
                                      overflow: TextOverflow.ellipsis)),
                            ]),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _loading ? null : _load,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: widget.onOpenSupport,
                    icon: const Icon(Icons.favorite_outline),
                    label: const Text('Support MolStr'),
                  ),
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse('https://njump.me/${widget.identity.npub}'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('View on njump'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final saved = await Navigator.of(context).push<bool>(
                        MaterialPageRoute<bool>(
                          builder: (_) => ProfileEditorPage(
                            identityService: widget.identityService,
                            relayService: widget.relayService,
                            relays: widget.relays,
                            current: profile,
                          ),
                        ),
                      );
                      if (saved == true) _load();
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit profile'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showAccountSwitcherSheet(
                      context: context,
                      identityService: widget.identityService,
                      activeIdentity: widget.identity,
                      onRefresh: widget.onAccountsChanged,
                    ),
                    icon: const Icon(Icons.switch_account),
                    label: const Text('Accounts'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: widget.onRemoveIdentity,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove local key'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabs,
              tabs: [
                Tab(text: 'Notes (${notes.length})'),
                Tab(text: 'Polls ($pollCount)'),
                Tab(text: 'Replies (${replies.length})'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: _notesTab(notes),
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: _pollCards(),
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: _notesTab(replies),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _bannerGradient() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFF4C1D95)],
          ),
        ),
      );
}
