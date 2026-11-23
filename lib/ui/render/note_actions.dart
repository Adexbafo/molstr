import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/nostr/interactions.dart';
import '../../core/nostr/nip19.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/note_engagement.dart';
import 'thread_page.dart';

class NoteActionBar extends StatefulWidget {
  const NoteActionBar({
    super.key,
    required this.event,
    required this.profile,
    required this.loadImages,
    this.engagement,
    this.inThread = false,
  });

  final NostrEvent event;
  final ProfileMetadata? profile;
  final bool loadImages;
  final NoteEngagement? engagement;
  final bool inThread;

  @override
  State<NoteActionBar> createState() => _NoteActionBarState();
}

class _NoteActionBarState extends State<NoteActionBar> {
  bool _busy = false;
  int _likeDelta = 0;
  int _repostDelta = 0;

  @override
  void didUpdateWidget(covariant NoteActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.id != widget.event.id ||
        oldWidget.engagement != widget.engagement) {
      _likeDelta = 0;
      _repostDelta = 0;
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _run(
    Future<int> Function(Interactions interactions) action,
    String success,
  ) async {
    final interactions = InteractionsScope.of(context);
    if (interactions == null || !interactions.canSign) {
      _message('Connect a key in Profile to interact.');
      return false;
    }
    setState(() => _busy = true);
    try {
      final ok = await action(interactions);
      _message(
        ok > 0
            ? '$success on $ok relay${ok == 1 ? '' : 's'}.'
            : 'No relay accepted it.',
      );
      return ok > 0;
    } catch (_) {
      _message('Could not sign or publish.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _like() async {
    final interactions = InteractionsScope.of(context);
    if (interactions?.isLiked(widget.event.id) ?? false) {
      _message('You already liked this note.');
      return;
    }
    final ok = await _run((i) => i.like(widget.event), 'Liked');
    if (ok && mounted) {
      setState(() => _likeDelta++);
    }
  }

  Future<void> _repost() async {
    final interactions = InteractionsScope.of(context);
    if (interactions?.isReposted(widget.event.id) ?? false) {
      _message('You already reposted this note.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Repost this note?'),
        content: const Text(
          'Your followers will see this note shared publicly from your key.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Repost'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final ok = await _run((i) => i.repost(widget.event), 'Reposted');
      if (ok && mounted) {
        setState(() => _repostDelta++);
      }
    }
  }

  void _openThread() {
    final interactions = InteractionsScope.of(context);
    if (interactions == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadPage(
          parent: widget.event,
          parentProfile: widget.profile,
          interactions: interactions,
          loadImages: widget.loadImages,
        ),
      ),
    );
  }

  Future<void> _openNjump(String path) async {
    await launchUrl(
      Uri.parse('https://njump.me/$path'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final interactions = InteractionsScope.of(context);
    final liked = interactions?.isLiked(widget.event.id) ?? false;
    final reposted = interactions?.isReposted(widget.event.id) ?? false;
    final accent = Theme.of(context).colorScheme.primary;
    final engagement = widget.engagement;

    final replyCount = engagement?.replies;
    final repostCount =
        engagement != null ? engagement.reposts + _repostDelta : null;
    final likeCount = engagement != null ? engagement.likes + _likeDelta : null;

    return Row(
      children: [
        if (!widget.inThread)
          _ActionCountButton(
            tooltip: 'Replies (observed on your relays)',
            icon: Icons.chat_bubble_outline,
            count: replyCount,
            onTap: _openThread,
          ),
        _ActionCountButton(
          tooltip: reposted
              ? 'Reposted (observed on your relays)'
              : 'Repost (observed on your relays)',
          icon: Icons.repeat,
          count: repostCount,
          color: reposted ? accent : null,
          onTap: _busy ? null : _repost,
        ),
        _ActionCountButton(
          tooltip: liked
              ? 'Liked (observed on your relays)'
              : 'Like (observed on your relays)',
          icon: liked ? Icons.favorite : Icons.favorite_border,
          count: likeCount,
          color: liked ? accent : null,
          onTap: _busy ? null : _like,
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        const Spacer(),
        PopupMenuButton<String>(
          tooltip: 'Open on njump.me',
          icon: const Icon(Icons.open_in_new, size: 18),
          onSelected: _openNjump,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: Nip19.encodeKey('note', widget.event.id),
              child: const Text('Open note on njump.me'),
            ),
            PopupMenuItem(
              value: widget.event.authorNpub,
              child: const Text('Open author profile on njump.me'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionCountButton extends StatelessWidget {
  const _ActionCountButton({
    required this.tooltip,
    required this.icon,
    required this.count,
    required this.onTap,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final int? count;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textStyle =
        Theme.of(context).textTheme.bodySmall?.copyWith(color: color);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              if (count != null) ...[
                const SizedBox(width: 4),
                Text('$count', style: textStyle),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
