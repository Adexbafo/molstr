import 'package:flutter/material.dart';

import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/note_engagement.dart';
import '../widgets/molstr_avatar.dart';
import 'note_actions.dart';
import 'note_card.dart' show formatTimestamp, shortNpub;

class PollCard extends StatelessWidget {
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
    final name = profile?.bestName ?? shortNpub(npub);

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
                  picture: profile?.picture,
                  loadImages: loadImages,
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
            for (final option in poll.options)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.dividerColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.radio_button_unchecked, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(option.label)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
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
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Voting arrives in a later MolStr version.',
              style: textTheme.bodySmall,
            ),
            if (provenance.isNotEmpty)
              Text(provenance, style: textTheme.bodySmall),
            const Divider(height: 20),
            NoteActionBar(
              event: poll.event,
              profile: profile,
              loadImages: loadImages,
              engagement: engagement,
            ),
          ],
        ),
      ),
    );
  }
}
