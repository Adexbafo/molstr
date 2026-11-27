import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/feed_curation.dart';
import '../../core/nostr/note_engagement.dart';
import '../../core/nostr/relay_service.dart';
import '../../ui/render/article_card.dart';
import '../../ui/render/note_card.dart';
import '../../ui/render/poll_card.dart';

/// The Home feed: recent notes, polls, and articles from the selected relays,
/// with opt-in filters. Nothing loads until the user asks for it.
class HomeFeedPage extends StatefulWidget {
  const HomeFeedPage({
    super.key,
    required this.relays,
    required this.relayService,
    required this.onOpenRelaySettings,
    required this.loadImages,
    this.refreshToken = 0,
    this.viewerPubkey,
  });

  final List<String> relays;
  final RelayService relayService;
  final VoidCallback onOpenRelaySettings;
  final bool loadImages;
  final int refreshToken;
  final String? viewerPubkey;

  @override
  State<HomeFeedPage> createState() => _HomeFeedPageState();
}

class _HomeFeedPageState extends State<HomeFeedPage> {
  /// The relay layer accepts at most 60 ids per count request.
  static const _countBatchSize = 60;

  FeedResult? _result;
  bool _loading = false;
  String _status = '';
  int _lastRefreshToken = 0;

  Map<String, NoteEngagement> _engagement = const {};
  int _engagementGeneration = 0;

  bool _hideReplies = true;
  bool _namedOnly = false;
  bool _hideRepeats = false;

  Set<String>? _trustedAuthors;
  bool _loadingTrust = false;

  @override
  void initState() {
    super.initState();
    _lastRefreshToken = widget.refreshToken;
  }

  @override
  void didUpdateWidget(covariant HomeFeedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != _lastRefreshToken &&
        _result != null &&
        !_loading) {
      _lastRefreshToken = widget.refreshToken;
      // Start the reload after this build finishes, not during it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadFeed();
      });
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadFeed() async {
    if (widget.relays.isEmpty || _loading) return;

    setState(() {
      _loading = true;
      _status = 'Connecting to ${widget.relays.length} relay(s)…';
    });

    try {
      final result = await widget.relayService.fetchFeed(
        widget.relays,
        onStatus: (status) {
          if (mounted) setState(() => _status = status);
        },
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
      unawaited(_loadEngagement(result));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Could not load the feed. Check your relays and try again.');
    }
  }

  /// Requests reply, like, repost, quote, and zap counts for every note and
  /// poll in [result]. Requests go in batches, so no item is left without one.
  Future<void> _loadEngagement(FeedResult result) async {
    final generation = ++_engagementGeneration;
    final ids = [
      for (final note in result.notes) note.id,
      for (final poll in result.polls) poll.id,
    ];
    if (ids.isEmpty || result.connectedRelays.isEmpty) return;

    for (var start = 0; start < ids.length; start += _countBatchSize) {
      final next = start + _countBatchSize;
      final end = next < ids.length ? next : ids.length;

      final counts = await widget.relayService.fetchNoteEngagement(
        ids.sublist(start, end),
        widget.relays,
      );
      if (!mounted || generation != _engagementGeneration) return;
      setState(() => _engagement = {..._engagement, ...counts});
    }
  }

  Future<void> _enableTrustFilter() async {
    final viewer = widget.viewerPubkey;
    if (viewer == null || _loadingTrust) return;

    setState(() => _loadingTrust = true);
    try {
      final trusted = await loadTrustSet(
        relayService: widget.relayService,
        viewer: viewer,
        relays: widget.relays,
      );
      if (!mounted) return;
      if (trusted == null) {
        _message(
          'No verified follow list was found on your selected relays. '
          'The Web of Trust filter stayed off.',
        );
        return;
      }
      setState(() => _trustedAuthors = trusted);
    } catch (_) {
      _message('Could not load your Web of Trust. The filter stayed off.');
    } finally {
      if (mounted) setState(() => _loadingTrust = false);
    }
  }

  bool _passesNameFilter(FeedResult result, String pubkey) =>
      (!_namedOnly || result.profiles.containsKey(pubkey)) &&
      (_trustedAuthors?.contains(pubkey) ?? true);

  Widget _connectPrompt(TextTheme textTheme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: [
            Text(
              'Connect to your relays',
              style: textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'MolStr does not connect automatically on startup. Loading the '
              'feed contacts only the relays listed below and verifies the '
              'signature on every note.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: widget.relays.isEmpty
                    ? const Text(
                        'No relays configured. Add at least one wss:// relay '
                        'in Settings.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Configured relays (${widget.relays.length})',
                            style: textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          for (final relay in widget.relays)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(relay),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: widget.relays.isEmpty ? null : _loadFeed,
              icon: const Icon(Icons.sync),
              label: const Text('Connect & load recent notes'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: widget.onOpenRelaySettings,
              icon: const Icon(Icons.tune),
              label: const Text('Manage relays'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectionFailed() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 56),
              const SizedBox(height: 12),
              const Text(
                'Could not connect to any configured relay. Check your internet '
                'connection or relay URLs.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loading ? null : _loadFeed,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: widget.onOpenRelaySettings,
                icon: const Icon(Icons.tune),
                label: const Text('Manage relays'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (_result == null && !_loading) {
      return _connectPrompt(textTheme);
    }

    if (_result == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_status),
          ],
        ),
      );
    }

    final result = _result!;
    if (result.connectedRelays.isEmpty) {
      return _connectionFailed();
    }

    // Filters run before anything is built, so the status line can report
    // how many copies were hidden.
    final matchingNotes = [
      for (final note in result.notes)
        if (!(_hideReplies && note.isReply) &&
            _passesNameFilter(result, note.pubkey))
          note,
    ];
    final visibleNotes =
        _hideRepeats ? collapseRepeatedNotes(matchingNotes) : matchingNotes;
    final repeatsHidden = matchingNotes.length - visibleNotes.length;

    final feedItems = <(int, Widget)>[
      for (final note in visibleNotes)
        (
          note.createdAt,
          KeyedSubtree(
            key: ValueKey('note:${note.id}'),
            child: NoteCard(
              event: note,
              profile: result.profiles[note.pubkey],
              provenance: relayProvenance(result.noteRelays[note.id]),
              loadImages: widget.loadImages,
              engagement: _engagement[note.id],
            ),
          ),
        ),
    ];

    for (final event in result.polls) {
      final poll = PollData.fromEvent(event);
      if (poll == null || !_passesNameFilter(result, event.pubkey)) {
        continue;
      }
      feedItems.add((
        event.createdAt,
        KeyedSubtree(
          key: ValueKey('poll:${event.id}'),
          child: PollCard(
            poll: poll,
            profile: result.profiles[event.pubkey],
            provenance: relayProvenance(result.noteRelays[event.id]),
            loadImages: widget.loadImages,
            engagement: _engagement[event.id],
          ),
        ),
      ));
    }

    for (final event in result.articles) {
      final article = ArticleData.fromEvent(event);
      if (article == null || !_passesNameFilter(result, event.pubkey)) {
        continue;
      }
      feedItems.add((
        event.createdAt,
        KeyedSubtree(
          key: ValueKey('article:${event.id}'),
          child: ArticleCard(
            article: article,
            profile: result.profiles[event.pubkey],
            provenance: relayProvenance(result.noteRelays[event.id]),
            loadImages: widget.loadImages,
          ),
        ),
      ));
    }

    feedItems.sort((a, b) => b.$1.compareTo(a.$1));

    final copyWord = repeatsHidden == 1 ? 'copy' : 'copies';
    final repeatNote =
        repeatsHidden == 0 ? '' : ' · $repeatsHidden repeated $copyWord hidden';
    final statusText =
        '${result.connectedRelays.length}/${widget.relays.length} relays '
        'connected · ${feedItems.length} items$repeatNote';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(statusText, style: textTheme.bodySmall),
              FilterChip(
                label: const Text('Hide replies'),
                selected: _hideReplies,
                onSelected: (selected) {
                  setState(() => _hideReplies = selected);
                },
              ),
              FilterChip(
                label: const Text('Named authors only'),
                selected: _namedOnly,
                onSelected: (selected) {
                  setState(() => _namedOnly = selected);
                },
              ),
              Tooltip(
                message:
                    'Shows your posts, posts from people you follow, and posts '
                    'from people they follow. Uses your selected relays.',
                child: FilterChip(
                  label: Text(
                    _loadingTrust ? 'Loading trust list…' : 'Web of Trust only',
                  ),
                  selected: _trustedAuthors != null,
                  onSelected: widget.viewerPubkey == null || _loadingTrust
                      ? null
                      : (selected) {
                          if (selected) {
                            _enableTrustFilter();
                          } else {
                            setState(() => _trustedAuthors = null);
                          }
                        },
                ),
              ),
              Tooltip(
                message:
                    'Keeps only the newest copy when the same author posts '
                    'identical text. Off by default, because someone posting '
                    '"gm" every day is not spam.',
                child: FilterChip(
                  label: const Text('Hide repeated notes'),
                  selected: _hideRepeats,
                  onSelected: (selected) {
                    setState(() => _hideRepeats = selected);
                  },
                ),
              ),
              TextButton.icon(
                onPressed: _loading ? null : _loadFeed,
                icon: _loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(_loading ? 'Refreshing…' : 'Refresh'),
              ),
              TextButton.icon(
                onPressed: widget.onOpenRelaySettings,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Relays'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: feedItems.isEmpty
              ? const Center(
                  child: Text('No matching notes returned from these relays.'),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final item in feedItems) item.$2,
                  ],
                ),
        ),
      ],
    );
  }
}
