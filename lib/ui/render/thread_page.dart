import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/nostr/interactions.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/note_engagement.dart';
import '../../core/nostr/relay_service.dart';
import 'note_card.dart';

class ThreadPage extends StatefulWidget {
  const ThreadPage({
    super.key,
    required this.parent,
    required this.parentProfile,
    required this.interactions,
    required this.loadImages,
  });

  final NostrEvent parent;
  final ProfileMetadata? parentProfile;
  final Interactions interactions;
  final bool loadImages;

  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<ThreadPage> {
  final _controller = TextEditingController();
  FeedResult? _result;
  Map<String, NoteEngagement> _engagement = const {};
  int _engagementGeneration = 0;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await widget.interactions.relayService
        .fetchThread(widget.parent.id, widget.interactions.relays);
    if (!mounted) return;
    setState(() {
      _result = result;
      _engagement = const {};
      _loading = false;
    });
    unawaited(_loadEngagement(result));
  }

  Future<void> _loadEngagement(FeedResult result) async {
    final generation = ++_engagementGeneration;
    final relays = result.connectedRelays.isNotEmpty
        ? result.connectedRelays
        : widget.interactions.relays;
    final noteIds = <String>[
      widget.parent.id,
      ...result.notes.map((reply) => reply.id),
    ];

    final counts = await widget.interactions.relayService
        .fetchNoteEngagement(noteIds, relays);
    if (!mounted || generation != _engagementGeneration) return;
    setState(() => _engagement = counts);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (!widget.interactions.canSign) {
      _message('Connect a key in Profile to reply.');
      return;
    }
    setState(() => _sending = true);
    try {
      final ok = await widget.interactions.reply(widget.parent, text);
      if (!mounted) return;
      if (ok > 0) {
        _controller.clear();
        _message('Reply published to $ok relay${ok == 1 ? '' : 's'}.');
        await _load();
      } else {
        _message('No relay accepted the reply.');
      }
    } catch (_) {
      _message('Could not sign or publish the reply.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final result = _result;
    final replies = result?.notes ?? const <NostrEvent>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thread'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: InteractionsScope(
        interactions: widget.interactions,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  NoteCard(
                    event: widget.parent,
                    profile: widget.parentProfile,
                    provenance: '',
                    loadImages: widget.loadImages,
                    engagement: _engagement[widget.parent.id],
                    inThread: true,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _loading
                        ? 'Loading replies…'
                        : 'Replies (${replies.length})',
                    style: textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (!_loading && replies.isEmpty)
                    const Text('No replies found on your relays yet.'),
                  if (result != null)
                    for (final reply in replies)
                      NoteCard(
                        event: reply,
                        profile: result.profiles[reply.pubkey],
                        provenance:
                            relayProvenance(result.noteRelays[reply.id]),
                        loadImages: widget.loadImages,
                        engagement: _engagement[reply.id],
                      ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: !_sending,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: widget.interactions.canSign
                              ? 'Write a public reply…'
                              : 'Connect a key in Profile to reply',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _sending ? null : _send,
                      child: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Reply'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
