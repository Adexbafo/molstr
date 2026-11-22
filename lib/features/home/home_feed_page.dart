import 'package:flutter/material.dart';

import '../../core/nostr/relay_service.dart';
import '../../ui/render/note_card.dart';

class HomeFeedPage extends StatefulWidget {
  const HomeFeedPage({
    super.key,
    required this.relays,
    required this.relayService,
    required this.onOpenRelaySettings,
    required this.loadImages,
    this.refreshToken = 0,
  });
  final bool loadImages;

  final List<String> relays;
  final RelayService relayService;
  final VoidCallback onOpenRelaySettings;
  final int refreshToken;

  @override
  State<HomeFeedPage> createState() => _HomeFeedPageState();
}

class _HomeFeedPageState extends State<HomeFeedPage> {
  FeedResult? _result;
  bool _loading = false;
  int _lastRefreshToken = 0;
  bool _hideReplies = true;
  String _status = '';

  Future<void> _loadFeed() async {
    if (widget.relays.isEmpty) return;

    setState(() {
      _loading = true;
      _status = 'Connecting to ${widget.relays.length} relay(s)...';
    });

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
      _lastRefreshToken = widget.refreshToken;
    });
  }

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
      _loadFeed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (_result == null && !_loading) {
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
                'MolStr does not connect automatically on startup. '
                'Loading the feed contacts only the relays listed below '
                'and cryptographically verifies every note.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: widget.relays.isEmpty
                      ? const Text(
                          'No relays configured. Add at least one wss:// relay in Settings.',
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
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

    if (_loading && _result == null) {
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
                  'Could not connect to any configured relay. '
                  'Check your internet connection or relay URLs.',
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

    final visibleNotes = _hideReplies
        ? result.notes.where((note) => !note.isReply).toList()
        : result.notes;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${result.connectedRelays.length}/${widget.relays.length} relays connected'
                ' · ${visibleNotes.length} verified notes',
                style: textTheme.bodySmall,
              ),
              FilterChip(
                label: const Text('Hide replies'),
                selected: _hideReplies,
                onSelected: (selected) {
                  setState(() => _hideReplies = selected);
                },
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
                label: Text(_loading ? 'Refreshing...' : 'Refresh'),
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
          child: visibleNotes.isEmpty
              ? const Center(
                  child: Text('No matching notes returned from these relays.'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: visibleNotes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final note = visibleNotes[index];
                    return NoteCard(
                      event: note,
                      profile: result.profiles[note.pubkey],
                      provenance: relayProvenance(result.noteRelays[note.id]),
                      loadImages: widget.loadImages,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
