import 'package:flutter/material.dart';

import '../../core/nostr/identity_service.dart';
import '../../core/nostr/nip19.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/private_messages.dart';
import '../../core/nostr/relay_service.dart';
import '../../ui/render/note_card.dart' show formatTimestamp;
import '../../ui/widgets/molstr_avatar.dart';
import 'chat_page.dart';
import 'message_service.dart';
import 'dart:async';
import '../../core/nostr/live_subscription.dart';

/// Turns what the user typed into a lowercase hex public key.
///
/// Accepts an npub (with or without a "nostr:" prefix) or a 64-character
/// hex key. Throws [FormatException] with a message that is safe to show.
String parseRecipientPubkey(String input) {
  var value = input.trim();
  if (value.toLowerCase().startsWith('nostr:')) {
    value = value.substring(6);
  }
  final lower = value.toLowerCase();

  if (lower.startsWith('nsec')) {
    throw const FormatException(
      'That is a private key. Never paste an nsec here.',
    );
  }

  if (lower.startsWith('npub1')) {
    try {
      return Nip19.hexFromNpub(lower).toLowerCase();
    } catch (_) {
      throw const FormatException(
        'That npub is not valid. Check that it was copied completely.',
      );
    }
  }

  if (RegExp(r'^[0-9a-f]{64}$').hasMatch(lower)) {
    return lower;
  }

  throw const FormatException('Enter an npub or a 64-character hex key.');
}

class MessagesPage extends StatefulWidget {
  const MessagesPage({
    super.key,
    required this.identityService,
    required this.relayService,
    required this.relays,
    required this.pubkey,
    required this.loadImages,
  });

  final IdentityService identityService;
  final RelayService relayService;
  final List<String> relays;
  final String? pubkey;
  final bool loadImages;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  late final MessageService _service;
  List<Conversation> _conversations = const [];
  Map<String, ProfileMetadata> _profiles = const {};
  String _status = '';
  String? _error;
  LiveSubscription? _live;
  Timer? _debounce;
  bool _loading = false;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _service = MessageService(
      identityService: widget.identityService,
      relayService: widget.relayService,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
    _startLive();
  }

  void _startLive() {
    final me = widget.pubkey;
    if (me == null || widget.relays.isEmpty) return;
    _live?.close();
    _live = LiveSubscription(
      relays: widget.relays,
      filter: giftWrapLiveFilter(me),
      onEvent: (_, __) => _scheduleReload(),
    )..start();
  }

  /// Several events can arrive together. Reload once, after they settle.
  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _live?.close();
    super.dispose();
  }

  Future<void> _load() async {
    final pubkey = widget.pubkey;
    if (pubkey == null) return;

    if (widget.relays.isEmpty) {
      setState(() {
        _error = 'No relays are configured. Add one in Settings.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _status = 'Starting…';
    });

    try {
      final messages = await _service.loadMessages(
        pubkey: pubkey,
        relays: widget.relays,
        onStatus: (status) {
          if (mounted) setState(() => _status = status);
        },
      );

      if (!mounted) return;

      final partners = <String>{};
      for (final message in messages) {
        final partner = message.partnerFor(pubkey);
        if (partner != null) partners.add(partner);
      }

      final profiles = <String, ProfileMetadata>{};
      if (partners.isNotEmpty) {
        final query = await widget.relayService.queryEvents(
          {
            'kinds': [0],
            'authors': partners.toList(),
          },
          widget.relays,
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
        _conversations = _service.conversationsFor(messages, pubkey);
        _profiles = profiles;
        _loading = false;
        _loadedOnce = true;
        _status = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadedOnce = true;
        _status = '';
        _error = 'Could not load messages. Check your connection and retry.';
      });
    }
  }

  String _preview(PrivateMessage message, String myPubkey) {
    final sender =
        message.senderPubkey == myPubkey.toLowerCase() ? 'You' : 'Them';
    final text = message.content.replaceAll('\n', ' ');
    final trimmed = text.length > 60 ? '${text.substring(0, 60)}…' : text;
    return '$sender: $trimmed';
  }

  void _openChat(String partnerPubkey) {
    Navigator.of(context)
        .push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(
          partnerPubkey: partnerPubkey,
          identityService: widget.identityService,
          relayService: widget.relayService,
          relays: widget.relays,
          loadImages: widget.loadImages,
          initialProfile: _profiles[partnerPubkey],
        ),
      ),
    )
        .then((_) {
      if (mounted) _load();
    });
  }

  Future<void> _startNewMessage() async {
    final me = widget.pubkey;
    if (me == null) return;

    final partner = await showDialog<String>(
      context: context,
      builder: (_) => _NewMessageDialog(myPubkey: me),
    );

    if (partner == null || !mounted) return;
    _openChat(partner);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final pubkey = widget.pubkey;

    if (pubkey == null) {
      return const Center(
        child: Text('Connect a key in Profile to use private messages.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Private messages observed on your selected relays.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _startNewMessage,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('New message'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(_loading ? 'Loading…' : 'Load messages'),
                  ),
                ],
              ),
              if (_loading && _status.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_status, style: textTheme.bodySmall),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody(textTheme, pubkey)),
      ],
    );
  }

  Widget _centered(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }

  Widget _buildBody(TextTheme textTheme, String pubkey) {
    if (_loading && _conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = _error;
    if (error != null && _conversations.isEmpty) {
      return _centered(error);
    }

    if (_conversations.isEmpty) {
      return _centered(
        _loadedOnce
            ? 'No private messages found on your relays yet.\n'
                'Press "New message" to start a conversation.'
            : 'Press "Load messages" to check your relays,\n'
                'or "New message" to start a conversation.',
      );
    }

    return ListView.separated(
      itemCount: _conversations.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final conversation = _conversations[index];
        final profile = _profiles[conversation.partnerPubkey];
        final name =
            profile?.bestName ?? shortNpubLabel(conversation.partnerPubkey);

        return ListTile(
          leading: MolStrAvatar(
            name: name,
            picture: profile?.picture,
            loadImages: widget.loadImages,
          ),
          title: Text(name, style: textTheme.titleSmall),
          subtitle: Text(
            _preview(conversation.lastMessage, pubkey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            formatTimestamp(conversation.lastMessage.createdAt),
            style: textTheme.bodySmall,
          ),
          onTap: () => _openChat(conversation.partnerPubkey),
        );
      },
    );
  }
}

class _NewMessageDialog extends StatefulWidget {
  const _NewMessageDialog({required this.myPubkey});

  final String myPubkey;

  @override
  State<_NewMessageDialog> createState() => _NewMessageDialogState();
}

class _NewMessageDialogState extends State<_NewMessageDialog> {
  final _controller = TextEditingController();
  String? _error;

  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _submit() {
    try {
      final pubkey = parseRecipientPubkey(_controller.text);
      if (pubkey == widget.myPubkey.toLowerCase()) {
        setState(() {
          _error = 'That is your own key. Choose someone else.';
        });
        return;
      }
      Navigator.of(context).pop(pubkey);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New message'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste the public key (npub) of the person you want to '
              'message. Check it carefully: MolStr cannot tell whether a '
              'key belongs to the person you expect.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Recipient npub',
                hintText: 'npub1…',
                errorText: _error,
                errorMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Open chat'),
        ),
      ],
    );
  }
}
