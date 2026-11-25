import 'package:flutter/material.dart';

import '../../core/nostr/identity_service.dart';
import '../../core/nostr/nip19.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/private_messages.dart';
import '../../core/nostr/relay_service.dart';
import '../../ui/render/note_card.dart' show formatTimestamp;
import '../../ui/widgets/molstr_avatar.dart';
import '../profile/user_profile_page.dart';
import '../../core/nostr/interactions.dart';
import 'message_service.dart';

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
  bool _loading = false;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _service = MessageService(
      identityService: widget.identityService,
      relayService: widget.relayService,
    );
  }

  Future<void> _load() async {
    final pubkey = widget.pubkey;
    if (pubkey == null || widget.relays.isEmpty) return;

    setState(() {
      _loading = true;
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

      // Fetch the other parties' profile metadata.
      final authors = <String>{};
      for (final message in messages) {
        final partner = message.partnerFor(pubkey);
        if (partner != null) authors.add(partner);
      }

      final profiles = <String, ProfileMetadata>{};
      if (authors.isNotEmpty) {
        final query = await widget.relayService.queryEvents(
          {
            'kinds': [0],
            'authors': authors.toList(),
          },
          widget.relays,
        );
        for (final event in query.events) {
          final profile = ProfileMetadata.fromKind0(event);
          if (profile != null) profiles[profile.pubkey] = profile;
        }
      }

      if (!mounted) return;
      setState(() {
        _conversations = _service.conversationsFor(messages, pubkey);
        _profiles = profiles;
        _loading = false;
        _loadedOnce = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadedOnce = true;
        _status = 'Could not load messages: $error';
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

  void _openConversation(Conversation conversation) {
    // ChatPage arrives in slice 3. For now, the list is the full feature:
    // tapping opens the partner's profile so you can follow / view them.
    final interactions = InteractionsScope.of(context);
    if (interactions == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfilePage(
          pubkey: conversation.partnerPubkey,
          interactions: interactions,
          loadImages: widget.loadImages,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final pubkey = widget.pubkey;

    if (pubkey == null) {
      return const Center(
        child: Text('Connect a key to read private messages.'),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Private messages observed on your selected relays.',
                ),
              ),
              FilledButton.icon(
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
        ),
        if (_status.isNotEmpty && _loading)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_status, style: textTheme.bodySmall),
          ),
        const Divider(height: 1),
        Expanded(
          child: _buildBody(textTheme, pubkey),
        ),
      ],
    );
  }

  Widget _buildBody(TextTheme textTheme, String pubkey) {
    if (_loading && _conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_conversations.isEmpty && _loadedOnce) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No private messages found on your relays yet.\n'
            'Chat pages arrive next; messages are already being decrypted.',
            textAlign: TextAlign.center,
          ),
        ),
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
        final npub = Nip19.npubFromHex(conversation.partnerPubkey);

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
          onTap: () => _openConversation(conversation),
        );
      },
    );
  }
}
