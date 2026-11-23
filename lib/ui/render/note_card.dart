import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/note_engagement.dart';
import '../widgets/molstr_avatar.dart';
import '../widgets/nip05_badge.dart';
import 'note_actions.dart';
import 'note_text.dart';

String formatTimestamp(int unixSeconds) {
  final created = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  final diff = DateTime.now().difference(created);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

String shortNpub(String npub) => npub.length <= 20
    ? npub
    : '${npub.substring(0, 12)}…${npub.substring(npub.length - 6)}';

String relayProvenance(Set<String>? urls) {
  if (urls == null || urls.isEmpty) return '';
  final hosts = urls.map((u) => Uri.tryParse(u)?.host ?? u).toList()..sort();
  return hosts.length == 1
      ? 'via ${hosts.first}'
      : 'via ${hosts.first} +${hosts.length - 1}';
}

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.event,
    required this.profile,
    required this.provenance,
    required this.loadImages,
    this.inThread = false,
    this.engagement,
  });

  final NostrEvent event;
  final ProfileMetadata? profile;
  final String provenance;
  final bool loadImages;
  final bool inThread;
  final NoteEngagement? engagement;

  Future<void> _copy(BuildContext context, String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final npub = event.authorNpub;
    final bestName = profile?.bestName ?? shortNpub(npub);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MolStrAvatar(
                  name: bestName,
                  picture: profile?.picture,
                  loadImages: loadImages,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bestName,
                        style: textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (bestName != shortNpub(npub))
                        Text(shortNpub(npub), style: textTheme.bodySmall),
                      if (profile?.nip05 != null)
                        Nip05Badge(
                          identifier: profile!.nip05!,
                          pubkey: event.pubkey,
                        ),
                    ],
                  ),
                ),
                Text(
                  formatTimestamp(event.createdAt),
                  style: textTheme.bodySmall,
                ),
                IconButton(
                  tooltip: 'Copy author npub',
                  onPressed: () => _copy(context, npub, 'Author npub copied.'),
                  icon: const Icon(Icons.copy, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 10),
            NoteText(content: event.content, loadImages: loadImages),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.verified_user_outlined, size: 12),
                const SizedBox(width: 4),
                const Text(
                  'signature verified',
                  style: TextStyle(fontSize: 11),
                ),
                if (provenance.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Text(provenance, style: textTheme.bodySmall),
                ],
              ],
            ),
            if (event.kind == 1)
              NoteActionBar(
                event: event,
                profile: profile,
                loadImages: loadImages,
                inThread: inThread,
                engagement: engagement,
              ),
          ],
        ),
      ),
    );
  }
}
