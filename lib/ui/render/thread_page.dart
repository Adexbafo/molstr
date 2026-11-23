import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/nostr/interactions.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/note_engagement.dart';
import '../widgets/molstr_avatar.dart';
import '../widgets/nip05_badge.dart';
import 'note_card.dart';

class ThreadPage extends StatefulWidget {
  const ThreadPage({
    super.key,
    required this.parent,
    required this.parentProfile,
    required this.interactions,
    required this.loadImages,
    this.onReplySent,
  });

  final NostrEvent parent;
  final ProfileMetadata? parentProfile;
  final Interactions interactions;
  final bool loadImages;
  final VoidCallback? onReplySent;

  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<ThreadPage> {
  final _controller = TextEditingController();
  NoteInteractions? _interactions;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await widget.interactions.relayService.fetchNoteInteractions(
      widget.parent.id,
      widget.interactions.relays,
    );
    if (!mounted) return;
    setState(() {
      _interactions = data;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (!widget.interactions.canSign) {
      _message('Connect a key in Profile to reply.');
      return;
    }
    setState(() => _sending = true);
    try {
      final ok = await widget.interactions.reply(widget.parent, text);
      if (!mounted) return;
      if (ok > 0) {
        _controller.clear();
        widget.onReplySent?.call();
        _message('Reply published to $ok relay${ok == 1 ? '' : 's'}.');
        await _load();
      } else {
        _message('No relay accepted the reply.');
      }
    } catch (_) {
      _message('Could not sign or publish the reply.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _copyNpub(String npub) async {
    await Clipboard.setData(ClipboardData(text: npub));
    _message('Author npub copied.');
  }

  Widget _buildNoteList(
    List<NostrEvent> events,
    String emptyMessage,
  ) {
    if (_loading && _interactions == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = _interactions;
    if (data == null || events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyMessage, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = events[index];
        return NoteCard(
          event: item,
          profile: data.profiles[item.pubkey],
          provenance: relayProvenance(data.eventRelays[item.id]),
          loadImages: widget.loadImages,
        );
      },
    );
  }

  Widget _buildUserList(
    List<NostrEvent> events,
    String emptyMessage,
  ) {
    if (_loading && _interactions == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = _interactions;
    if (data == null || events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyMessage, textAlign: TextAlign.center),
        ),
      );
    }

    final textTheme = Theme.of(context).textTheme;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = events[index];
        final profile = data.profiles[item.pubkey];
        final npub = item.authorNpub;
        final name = profile?.bestName ?? shortNpub(npub);
        final provenance = relayProvenance(data.eventRelays[item.id]);

        return Card(
          child: ListTile(
            leading: MolStrAvatar(
              name: name,
              picture: profile?.picture,
              loadImages: widget.loadImages,
            ),
            title: Text(
              name,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name != shortNpub(npub))
                  Text(shortNpub(npub), style: textTheme.bodySmall),
                if (profile?.nip05 != null)
                  Nip05Badge(identifier: profile!.nip05!, pubkey: item.pubkey),
                Text(
                  '${formatTimestamp(item.createdAt)}'
                  '${provenance.isNotEmpty ? ' · $provenance' : ''}',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Copy npub',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => _copyNpub(npub),
                ),
                IconButton(
                  tooltip: 'Open profile on njump.me',
                  icon: const Icon(Icons.open_in_new, size: 18),
                  onPressed: () => launchUrl(
                    Uri.parse('https://njump.me/$npub'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _interactions;
    final replies = data?.replies ?? const <NostrEvent>[];
    final likes = data?.likes ?? const <NostrEvent>[];
    final reposts = data?.reposts ?? const <NostrEvent>[];
    final quotes = data?.quotes ?? const <NostrEvent>[];

    final parentEngagement = data != null
        ? NoteEngagement(
            replies: replies.length,
            likes: likes.length,
            reposts: reposts.length,
            quotes: quotes.length,
          )
        : null;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Thread & Interactions'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        body: InteractionsScope(
          interactions: widget.interactions,
          child: Column(
            children: [
              Expanded(
                child: NestedScrollView(
                  headerSliverBuilder: (context, _) => [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NoteCard(
                              event: widget.parent,
                              profile: widget.parentProfile,
                              provenance: '',
                              loadImages: widget.loadImages,
                              engagement: parentEngagement,
                              inThread: true,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Interactions observed on your connected relays.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: TabBar(
                        isScrollable: true,
                        tabs: [
                          Tab(text: 'Replies (${replies.length})'),
                          Tab(text: 'Likes (${likes.length})'),
                          Tab(text: 'Reposts (${reposts.length})'),
                          Tab(text: 'Quotes (${quotes.length})'),
                          Tab(
                            text:
                                'Zaps (${data?.totalZapSats != null && data!.totalZapSats > 0 ? '${formatSats(data.totalZapSats)} sats' : '${data?.zaps.length ?? 0}'})',
                          ),
                        ],
                      ),
                    ),
                  ],
                  body: TabBarView(
                    children: [
                      _buildNoteList(
                        replies,
                        'No replies observed on your relays yet.',
                      ),
                      _buildUserList(
                        likes,
                        'No likes observed on your relays yet.',
                      ),
                      _buildUserList(
                        reposts,
                        'No reposts observed on your relays yet.',
                      ),
                      _buildNoteList(
                        quotes,
                        'No quote notes observed on your relays yet.',
                      ),
                      _buildUserList(
                        data?.zaps ?? const <NostrEvent>[],
                        'No zap receipts observed on your relays yet.',
                      ),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          enabled: !_sending,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: widget.interactions.canSign
                                ? 'Write a public reply…'
                                : 'Connect a key in Profile to reply',
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _sending ? null : _send,
                        child: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Reply'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
