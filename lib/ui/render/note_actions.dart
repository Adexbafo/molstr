import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/nostr/interactions.dart';
import '../../core/nostr/nip19.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/note_engagement.dart';
import '../../core/payments/monero.dart';
import '../payments/monero_sheet.dart';
import '../payments/zap_sheet.dart';
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
  int _replyDelta = 0;
  int _likeDelta = 0;
  int _repostDelta = 0;

  @override
  void didUpdateWidget(covariant NoteActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.id != widget.event.id ||
        oldWidget.engagement != widget.engagement) {
      _replyDelta = 0;
      _likeDelta = 0;
      _repostDelta = 0;
    }
  }

  String _recipientName() {
    final best = widget.profile?.bestName;
    if (best != null && best.isNotEmpty) return best;
    final npub = widget.event.authorNpub;
    if (npub.length <= 20) return npub;
    return '${npub.substring(0, 12)}…${npub.substring(npub.length - 6)}';
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
    if (ok && mounted) setState(() => _likeDelta++);
  }

  Future<void> _openRepostOrQuote() async {
    final interactions = InteractionsScope.of(context);
    if (interactions == null || !interactions.canSign) {
      _message('Connect a key in Profile to interact.');
      return;
    }
    final alreadyReposted = interactions.isReposted(widget.event.id);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.repeat),
              title: Text(alreadyReposted ? 'Already reposted' : 'Repost'),
              subtitle: const Text('Share directly (kind 6)'),
              enabled: !alreadyReposted,
              onTap: () => Navigator.of(context).pop('repost'),
            ),
            ListTile(
              leading: const Icon(Icons.format_quote),
              title: const Text('Quote note'),
              subtitle: const Text('Public note quoting this post (NIP-18)'),
              onTap: () => Navigator.of(context).pop('quote'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'repost') {
      await _confirmAndRepost();
    } else if (choice == 'quote') {
      await _openQuoteDialog();
    }
  }

  Future<void> _confirmAndRepost() async {
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
      if (ok && mounted) setState(() => _repostDelta++);
    }
  }

  Future<void> _openQuoteDialog() async {
    final controller = TextEditingController();
    final preview = widget.event.content.length > 140
        ? '${widget.event.content.substring(0, 140)}…'
        : widget.event.content;
    final commentary = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quote note'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'Add your thoughts… #hashtags',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text(preview, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Publish quote'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (commentary == null || commentary.isEmpty || !mounted) return;
    final ok = await _run((i) => i.quote(widget.event, commentary), 'Quoted');
    if (ok && mounted) setState(() => _repostDelta++);
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
          onReplySent: () {
            if (mounted) setState(() => _replyDelta++);
          },
        ),
      ),
    );
  }

  Future<void> _openZap() async {
    final interactions = InteractionsScope.of(context);
    if (interactions == null || !interactions.canSign) {
      _message('Connect a key in Profile to zap.');
      return;
    }
    final lud16 = widget.profile?.lud16;
    if (lud16 == null || lud16.trim().isEmpty) {
      _message('Author has no Lightning address.');
      return;
    }
    await showZapSheet(
      context: context,
      recipientName: _recipientName(),
      recipientLud16: lud16.trim(),
      recipientPubkeyHex: widget.event.pubkey,
      noteEvent: widget.event.kind == 1 ? widget.event : null,
      relays: interactions.relays,
      identityService: interactions.identityService,
    );
  }

  Future<void> _openMoneroTip() async {
    final address = widget.profile?.moneroAddress;
    if (address == null || address.trim().isEmpty) {
      _message('Author has no Monero address.');
      return;
    }
    if (!isValidMoneroAddress(address)) {
      _message('Author Monero address looks invalid.');
      return;
    }
    final content = widget.event.content;
    final preview =
        content.length > 120 ? '${content.substring(0, 120)}…' : content;
    await showMoneroSheet(
      context: context,
      recipientName: _recipientName(),
      moneroAddress: address.trim(),
      notePreview: preview,
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

    final replyCount = engagement != null
        ? engagement.replies + _replyDelta
        : (_replyDelta > 0 ? _replyDelta : null);
    final repostCount = engagement != null
        ? engagement.reposts + engagement.quotes + _repostDelta
        : (_repostDelta > 0 ? _repostDelta : null);
    final likeCount = engagement != null
        ? engagement.likes + _likeDelta
        : (_likeDelta > 0 ? _likeDelta : null);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.inThread)
            _ActionCountButton(
              tooltip: 'Replies & interactions (observed on your relays)',
              icon: Icons.chat_bubble_outline,
              count: replyCount,
              onTap: _openThread,
            ),
          _ActionCountButton(
            tooltip: 'Repost or quote (observed on your relays)',
            icon: Icons.repeat,
            count: repostCount,
            color: reposted ? accent : null,
            onTap: _busy ? null : _openRepostOrQuote,
          ),
          _ActionCountButton(
            tooltip: 'Like (observed on your relays)',
            icon: liked ? Icons.favorite : Icons.favorite_border,
            count: likeCount,
            color: liked ? accent : null,
            onTap: _busy ? null : _like,
          ),
          IconButton(
            tooltip: 'Zap with Bitcoin Lightning (public)',
            icon: const Icon(Icons.bolt_outlined, size: 20),
            onPressed: _busy ? null : _openZap,
          ),
          IconButton(
            tooltip: 'Tip with Monero (private)',
            icon: const Icon(Icons.shield_outlined, size: 20),
            onPressed: _openMoneroTip,
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
      ),
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
