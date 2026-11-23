import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/nostr/interactions.dart';
import '../../core/nostr/nip19.dart';
import '../../core/nostr/nostr_event.dart';
import 'thread_page.dart';

class NoteActionBar extends StatefulWidget {
  const NoteActionBar({
    super.key,
    required this.event,
    required this.profile,
    required this.loadImages,
    this.inThread = false,
  });

  final NostrEvent event;
  final ProfileMetadata? profile;
  final bool loadImages;
  final bool inThread;

  @override
  State<NoteActionBar> createState() => _NoteActionBarState();
}

class _NoteActionBarState extends State<NoteActionBar> {
  bool _busy = false;

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(
    Future<int> Function(Interactions interactions) action,
    String success,
  ) async {
    final interactions = InteractionsScope.of(context);
    if (interactions == null || !interactions.canSign) {
      _message('Connect a key in Profile to interact.');
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await action(interactions);
      _message(ok > 0
          ? '$success on $ok relay${ok == 1 ? '' : 's'}.'
          : 'No relay accepted it.');
    } catch (_) {
      _message('Could not sign or publish.');
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
    await _run((i) => i.like(widget.event), 'Liked');
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
      await _run((i) => i.repost(widget.event), 'Reposted');
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

    return Row(
      children: [
        if (!widget.inThread)
          IconButton(
            tooltip: 'Replies',
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            onPressed: _openThread,
          ),
        IconButton(
          tooltip: reposted ? 'Reposted' : 'Repost',
          icon: Icon(
            Icons.repeat,
            size: 18,
            color: reposted ? accent : null,
          ),
          onPressed: _busy ? null : _repost,
        ),
        IconButton(
          tooltip: liked ? 'Liked' : 'Like',
          icon: Icon(
            liked ? Icons.favorite : Icons.favorite_border,
            size: 18,
            color: liked ? accent : null,
          ),
          onPressed: _busy ? null : _like,
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(left: 4),
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
