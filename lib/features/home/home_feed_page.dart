import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/relay_service.dart';

class HomeFeedPage extends StatefulWidget {
  const HomeFeedPage({
    super.key,
    required this.relays,
    required this.relayService,
    required this.onOpenRelaySettings,
  });

  final List<String> relays;
  final RelayService relayService;
  final VoidCallback onOpenRelaySettings;

  @override
  State<HomeFeedPage> createState() => _HomeFeedPageState();
}

class _HomeFeedPageState extends State<HomeFeedPage> {
  FeedResult? _result;
  bool _loading = false;
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
  });
}

  Future<void> _copyNpub(String npub) async {
    await Clipboard.setData(ClipboardData(text: npub));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Author npub copied.')),
    );
  }

  String _shortNpub(String npub) {
    if (npub.length <= 20) return npub;
    return '${npub.substring(0, 12)}…${npub.substring(npub.length - 6)}';
  }

  String _formatTimestamp(int unixSeconds) {
    final created = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    final diff = DateTime.now().difference(created);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatRelayHosts(Set<String>? urls) {
    if (urls == null || urls.isEmpty) return '';
    final hosts = urls
        .map((u) => Uri.tryParse(u)?.host ?? u)
        .toList()
      ..sort();
    if (hosts.length == 1) return 'via ${hosts.first}';
    return 'via ${hosts.first} +${hosts.length - 1}';
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
                    final profile = result.profiles[note.pubkey];
                    final npub = note.authorNpub;
                    final authorLabel =
                        profile?.bestName ?? _shortNpub(npub);
                    final provenance =
                        _formatRelayHosts(result.noteRelays[note.id]);

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        authorLabel,
                                        style: textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        _shortNpub(npub),
                                        style: textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  _formatTimestamp(note.createdAt),
                                  style: textTheme.bodySmall,
                                ),
                                IconButton(
                                  tooltip: 'Copy author npub',
                                  onPressed: () => _copyNpub(npub),
                                  icon: const Icon(Icons.copy, size: 16),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SelectableText(note.content),
                            if (provenance.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(provenance, style: textTheme.bodySmall),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}