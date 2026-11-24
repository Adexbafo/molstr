import 'package:flutter/material.dart';

import '../../core/nostr/interactions.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/note_engagement.dart';
import '../../core/nostr/poll_results.dart';
import '../widgets/molstr_avatar.dart';
import 'note_actions.dart';
import 'note_card.dart' show formatTimestamp, shortNpub;

class PollCard extends StatefulWidget {
  const PollCard({
    super.key,
    required this.poll,
    required this.profile,
    required this.provenance,
    required this.loadImages,
    this.engagement,
  });

  final PollData poll;
  final ProfileMetadata? profile;
  final String provenance;
  final bool loadImages;
  final NoteEngagement? engagement;

  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  PollResults? _results;
  bool _loading = true;
  bool _voting = false;
  final Set<String> _selected = {};

  PollData get poll => widget.poll;
  bool get _closed =>
      poll.endsAt != null &&
      DateTime.now().millisecondsSinceEpoch ~/ 1000 > poll.endsAt!;
  bool get _voted => _results?.myResponses.isNotEmpty ?? false;

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadResults() async {
    final interactions = InteractionsScope.of(context);
    if (interactions == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final me = await interactions.identityService.currentIdentity();
      final results = await interactions.relayService.fetchPollResults(
        poll.event.id,
        interactions.relays,
        myPubkey: me?.pubkey,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      // Never leave the card stuck in loading: show empty results.
      if (!mounted) return;
      setState(() {
        _results = const PollResults(
          optionCounts: {},
          voterCount: 0,
          myResponses: [],
        );
        _loading = false;
      });
    }
  }

  Future<void> _toggleOption(String code) async {
    // Selection is local: never blocked by loading results.
    if (_closed || _voting) return;
    final interactions = InteractionsScope.of(context);
    if (interactions == null) {
      _message('Connect a key in Profile to vote.');
      return;
    }
    setState(() {
      if (poll.multipleChoice) {
        if (_selected.contains(code)) {
          _selected.remove(code);
        } else {
          _selected.add(code);
        }
      } else {
        _selected
          ..clear()
          ..add(code);
      }
    });
  }

  Future<void> _submitVote() async {
    final interactions = InteractionsScope.of(context);
    if (interactions == null || !interactions.canSign) {
      _message('Connect a key in Profile to vote.');
      return;
    }
    if (_selected.isEmpty) {
      _message('Tap an option first to vote.');
      return;
    }
    setState(() => _voting = true);
    try {
      final ok = await interactions.votePoll(poll.event, _selected.toList());
      if (!mounted) return;
      if (ok > 0) {
        _selected.clear();
        _message('Vote published to $ok relay${ok == 1 ? '' : 's'}.');
        await _loadResults();
      } else {
        _message('No relay accepted your vote.');
      }
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  String _formatEndsAt(int unix) {
    final diff = DateTime.fromMillisecondsSinceEpoch(unix * 1000)
        .difference(DateTime.now());
    if (diff.isNegative) return 'Closed';
    if (diff.inMinutes < 60) return 'Ends in ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'Ends in ${diff.inHours}h';
    return 'Ends in ${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final event = poll.event;
    final npub = event.authorNpub;
    final name = widget.profile?.bestName ?? shortNpub(npub);
    final voteOptions = _selected;
    final mine = _results?.myResponses.toSet() ?? const <String>{};
    final totalVoters = _results?.voterCount;
    final selectable = !_closed && !_voting;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MolStrAvatar(
                  name: name,
                  picture: widget.profile?.picture,
                  loadImages: widget.loadImages,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (name != shortNpub(npub))
                        Text(shortNpub(npub), style: textTheme.bodySmall),
                    ],
                  ),
                ),
                Text(
                  formatTimestamp(event.createdAt),
                  style: textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(event.content, style: textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final option in poll.options) ...[
              _OptionTile(
                label: option.label,
                selected: voteOptions.contains('${option.index}'),
                chosen: mine.contains('${option.index}'),
                votes: _results?.optionCounts['${option.index}'],
                totalVoters: totalVoters,
                enabled: selectable,
                multipleChoice: poll.multipleChoice,
                onTap: () => _toggleOption('${option.index}'),
              ),
              const SizedBox(height: 6),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.poll, size: 14),
                  label: Text(
                    poll.multipleChoice ? 'Multiple choice' : 'Single choice',
                  ),
                ),
                if (poll.endsAt != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(_formatEndsAt(poll.endsAt!)),
                  ),
                if (totalVoters != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Voters observed: $totalVoters'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_voted)
                  const Text('You voted on this poll.')
                else if (_closed)
                  const Text('Voting closed.')
                else
                  FilledButton.icon(
                    // Always tappable: explains itself when nothing selected.
                    onPressed: _voting ? null : _submitVote,
                    icon: _voting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.how_to_vote),
                    label: Text(_voting ? 'Publishing…' : 'Vote'),
                  ),
                const Spacer(),
                Text(
                  _loading
                      ? 'Loading poll results…'
                      : 'Counts observed on your relays.',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (widget.provenance.isNotEmpty)
              Text(widget.provenance, style: textTheme.bodySmall),
            const Divider(height: 20),
            NoteActionBar(
              event: poll.event,
              profile: widget.profile,
              loadImages: widget.loadImages,
              engagement: widget.engagement,
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.chosen,
    required this.votes,
    required this.totalVoters,
    required this.enabled,
    required this.multipleChoice,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool chosen;
  final int? votes;
  final int? totalVoters;
  final bool enabled;
  final bool multipleChoice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final fraction = (totalVoters == null || totalVoters == 0 || votes == null)
        ? 0.0
        : votes! / totalVoters!;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Stack(
          children: [
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction,
                child: ColoredBox(color: accent.withValues(alpha: 0.18)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    multipleChoice
                        ? (selected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank)
                        : (selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked),
                    size: 18,
                    color: selected ? accent : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label)),
                  if (chosen)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.how_to_reg, size: 16, color: accent),
                    ),
                  if (votes != null) Text('$votes'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
