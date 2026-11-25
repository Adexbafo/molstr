import 'package:flutter/material.dart';

import '../../core/nostr/interactions.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/note_engagement.dart';
import '../../core/nostr/poll_results.dart';
import '../../features/profile/user_profile_page.dart';
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
  Map<String, ProfileMetadata> _profiles = const {};
  bool _loading = true;
  bool _voting = false;
  bool _started = false;
  final Set<String> _selected = {};

  PollData get poll => widget.poll;

  bool get _closed =>
      poll.endsAt != null &&
      DateTime.now().millisecondsSinceEpoch ~/ 1000 > poll.endsAt!;

  Set<String> get _previousVote => _results?.myResponses.toSet() ?? const {};

  bool get _voted => _previousVote.isNotEmpty;

  String _describeResponse(List<String> responses) {
    if (responses.isEmpty) return 'chose nothing';
    final byIndex = {
      for (final o in poll.options) '${o.index}': o.label,
    };
    final readable =
        responses.map((code) => byIndex[code] ?? 'option $code').join(', ');
    return 'Voted: $readable';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _loadResults();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _loadResults() async {
    final interactions = InteractionsScope.of(context);
    if (interactions == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final me = await interactions.identityService.currentIdentity();
    final results = await interactions.relayService.fetchPollResults(
      poll.event.id,
      interactions.relays,
      myPubkey: me?.pubkey,
    );

    final profiles = <String, ProfileMetadata>{};
    final authors = results.voters.map((voter) => voter.pubkey).take(30);
    if (results.available && authors.isNotEmpty) {
      final query = await interactions.relayService.queryEvents(
        {
          'kinds': [0],
          'authors': authors.toList(),
        },
        interactions.relays,
      );
      for (final event in query.events) {
        final profile = ProfileMetadata.fromKind0(event);
        if (profile == null) continue;
        final existing = profiles[profile.pubkey];
        if (existing == null || profile.createdAt > existing.createdAt) {
          profiles[profile.pubkey] = profile;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _results = results;
      _profiles = profiles;
      _loading = false;
    });
  }

  void _toggleOption(String code) {
    if (_closed || _voting) return;
    final interactions = InteractionsScope.of(context);
    if (interactions == null || !interactions.canSign) {
      _message('Connect a key in Profile to vote.');
      return;
    }

    setState(() {
      if (poll.multipleChoice) {
        _selected.contains(code) ? _selected.remove(code) : _selected.add(code);
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
      _message('Tap an option first.');
      return;
    }

    setState(() => _voting = true);
    try {
      final accepted = await interactions.votePoll(
        poll.event,
        _selected.toList(),
      );
      if (!mounted) return;
      if (accepted > 0) {
        _selected.clear();
        _message(
          'Vote published to $accepted relay${accepted == 1 ? '' : 's'}.',
        );
        await _loadResults();
      } else {
        _message('No relay accepted your vote.');
      }
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  String _endsAt(int unix) {
    final remaining = DateTime.fromMillisecondsSinceEpoch(unix * 1000)
        .difference(DateTime.now());
    if (remaining.isNegative) return 'Closed';
    if (remaining.inHours < 1) return 'Ends in ${remaining.inMinutes}m';
    if (remaining.inDays < 1) return 'Ends in ${remaining.inHours}h';
    return 'Ends in ${remaining.inDays}d';
  }

  bool _shownSelected(String code) {
    if (_selected.isNotEmpty) return _selected.contains(code);
    return _previousVote.contains(code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = poll.event;
    final npub = event.authorNpub;
    final name = widget.profile?.bestName ?? shortNpub(npub);
    final voters = _results?.voters ?? const <PollVoter>[];

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
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (name != shortNpub(npub))
                        Text(shortNpub(npub), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Text(
                  formatTimestamp(event.createdAt),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(event.content, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final option in poll.options) ...[
              _OptionTile(
                label: option.label,
                selected: _shownSelected('${option.index}'),
                votes: _results?.optionCounts['${option.index}'],
                totalVoters: _results?.voterCount,
                enabled: !_closed && !_voting,
                multiple: poll.multipleChoice,
                onTap: () => _toggleOption('${option.index}'),
              ),
              const SizedBox(height: 6),
            ],
            Wrap(
              spacing: 8,
              children: [
                Chip(
                  label: Text(
                    poll.multipleChoice ? 'Multiple choice' : 'Single choice',
                  ),
                ),
                if (poll.endsAt != null)
                  Chip(label: Text(_endsAt(poll.endsAt!))),
                if (_results?.available == true)
                  Chip(label: Text('Voters observed: ${voters.length}')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _loading
                  ? 'Loading votes…'
                  : _results?.available == false
                      ? 'Votes unavailable. Refresh and check your relays.'
                      : 'Counts observed on your relays.',
              style: theme.textTheme.bodySmall,
            ),
            if (voters.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Voters', style: theme.textTheme.titleSmall),
              for (final voter in voters.take(12))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: MolStrAvatar(
                    name: _profiles[voter.pubkey]?.bestName ?? voter.pubkey,
                    picture: _profiles[voter.pubkey]?.picture,
                    loadImages: widget.loadImages,
                    radius: 16,
                  ),
                  title: Text(
                    _profiles[voter.pubkey]?.bestName ??
                        shortNpub(voter.pubkey),
                  ),
                  subtitle: Text(_describeResponse(voter.responses)),
                  onTap: () {
                    final interactions = InteractionsScope.of(context);
                    if (interactions == null) return;
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => UserProfilePage(
                          pubkey: voter.pubkey,
                          interactions: interactions,
                          loadImages: widget.loadImages,
                        ),
                      ),
                    );
                  },
                ),
            ],
            const SizedBox(height: 8),
            if (_voted)
              const Text('You voted on this poll.')
            else if (_closed)
              const Text('Voting closed.')
            else
              FilledButton.icon(
                onPressed: _voting ? null : _submitVote,
                icon: const Icon(Icons.how_to_vote),
                label: Text(_voting ? 'Publishing…' : 'Vote'),
              ),
            if (widget.provenance.isNotEmpty)
              Text(widget.provenance, style: theme.textTheme.bodySmall),
            const Divider(height: 20),
            NoteActionBar(
              event: event,
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
    required this.votes,
    required this.totalVoters,
    required this.enabled,
    required this.multiple,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final int? votes;
  final int? totalVoters;
  final bool enabled;
  final bool multiple;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final fraction = totalVoters == null || totalVoters == 0 || votes == null
        ? 0.0
        : votes! / totalVoters!;

    return Material(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.35),
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
                child: ColoredBox(color: color.withValues(alpha: 0.18)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    multiple
                        ? selected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank
                        : selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                    color: selected ? color : null,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label)),
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
