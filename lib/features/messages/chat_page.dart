import 'package:flutter/material.dart';

import '../../core/nostr/identity_service.dart';
import '../../core/nostr/nip19.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/private_messages.dart';
import '../../core/nostr/relay_service.dart';
import '../../ui/render/note_card.dart' show formatTimestamp, shortNpub;
import '../../ui/widgets/molstr_avatar.dart';
import 'message_service.dart';
import 'dart:async';
import '../../core/nostr/live_subscription.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.partnerPubkey,
    required this.identityService,
    required this.relayService,
    required this.relays,
    required this.loadImages,
    this.initialMessages,
    this.initialProfile,
  });

  final String partnerPubkey;
  final IdentityService identityService;
  final RelayService relayService;
  final List<String> relays;
  final bool loadImages;
  final List<PrivateMessage>? initialMessages;
  final ProfileMetadata? initialProfile;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  LiveSubscription? _live;
  Timer? _debounce;
  final _scrollController = ScrollController();

  late final MessageService _service;
  List<PrivateMessage> _messages = const [];
  ProfileMetadata? _profile;
  String? _myPubkey;
  bool _loading = true;
  bool _sending = false;
  String? _status;

  String get _partnerKey => widget.partnerPubkey.toLowerCase();

  @override
  void initState() {
    super.initState();
    _service = MessageService(
      identityService: widget.identityService,
      relayService: widget.relayService,
    );
    _profile = widget.initialProfile;
    if (widget.initialMessages != null && widget.initialMessages!.isNotEmpty) {
      _messages = widget.initialMessages!;
      _loading = false;
    }
    _bootstrap();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _live?.close();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startLive() {
    final me = _myPubkey;
    if (me == null) return;
    _live?.close();
    _live = LiveSubscription(
      relays: widget.relays,
      filter: giftWrapLiveFilter(me),
      onEvent: (_, __) => _scheduleReload(),
    )..start();
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      if (mounted && !_sending) _load();
    });
  }

  Future<void> _bootstrap() async {
    final me = await widget.identityService.currentIdentity();
    if (!mounted) return;
    setState(() => _myPubkey = me?.pubkey);
    if (me != null) {
      await _load();
      _startLive();
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    final me = _myPubkey;
    if (me == null) return;

    setState(() {
      _loading = true;
      _status = 'Loading…';
    });

    try {
      final messages = await _service.loadMessages(
        pubkey: me,
        relays: widget.relays,
        onStatus: (status) {
          if (mounted) setState(() => _status = status);
        },
      );

      final filtered = messages
          .where((message) => message.partnerFor(me) == _partnerKey)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      var profile = _profile;
      if (profile == null) {
        final query = await widget.relayService.queryEvents(
          {
            'kinds': [0],
            'authors': [_partnerKey],
          },
          widget.relays,
        );
        for (final event in query.events) {
          final parsed = ProfileMetadata.fromKind0(event);
          if (parsed != null) {
            profile = parsed;
            break;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _messages = filtered;
        _profile = profile;
        _loading = false;
        _status = null;
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Could not load messages: $error';
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final me = _myPubkey;
    final text = _controller.text.trim();
    if (me == null) {
      _message('Connect a key in Profile to send messages.');
      return;
    }
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      final result = await _service.sendMessage(
        senderPubkey: me,
        partnerPubkey: _partnerKey,
        content: text,
        relays: widget.relays,
      );

      if (!mounted) return;
      _controller.clear();

      if (!result.deliveredToPartner) {
        _message(
          'No relay accepted the copy for your partner. '
          'Nothing was delivered.',
        );
      } else if (!result.savedForSelf) {
        _message(
          'Delivered to ${result.recipientAccepted} relay(s), but the copy '
          'to yourself was rejected. This device may not see the message '
          'after a restart.',
        );
      } else {
        _message(
          'Sent to ${result.recipientAccepted} '
          'relay${result.recipientAccepted == 1 ? '' : 's'}.',
        );
      }

      await _load();
    } catch (error) {
      _message(
        'Could not send: '
        '${error.toString().replaceFirst('Exception: ', '')}',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _partnerName() {
    final profile = _profile;
    if (profile != null) return profile.bestName;
    return shortNpub(Nip19.npubFromHex(_partnerKey));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = _myPubkey;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            MolStrAvatar(
              name: _partnerName(),
              picture: _profile?.picture,
              loadImages: widget.loadImages,
              radius: 16,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _partnerName(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildList(theme, me)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_sending && me != null,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: me == null
                            ? 'Connect a key to send messages'
                            : 'Write a private message…',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _sending || me == null ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send, size: 18),
                    label: Text(_sending ? 'Sending…' : 'Send'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ThemeData theme, String? me) {
    if (me == null) {
      return const Center(
        child: Text('Connect a key in Profile to read messages.'),
      );
    }
    if (_loading && _messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(_status ?? 'Loading messages…'),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No messages yet.\n'
            'Messages you send and receive appear here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMine = message.senderPubkey == me.toLowerCase();
        final bubbleColor = isMine
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest;

        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Card(
              color: bubbleColor,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      message.content,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isMine
                          ? 'You · ${formatTimestamp(message.createdAt)}'
                          : '${_partnerName()} · '
                              '${formatTimestamp(message.createdAt)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
