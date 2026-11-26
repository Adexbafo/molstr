import 'package:flutter/material.dart';

import '../../core/nostr/interactions.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/note_engagement.dart';
import '../../core/nostr/relay_service.dart';
import '../../ui/render/note_card.dart';
import '../../ui/render/thread_page.dart';
import '../../ui/widgets/molstr_avatar.dart';
import '../profile/user_profile_page.dart';
import 'dart:async';

import '../../core/nostr/live_subscription.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.relayService,
    required this.relays,
    required this.pubkey,
    required this.loadImages,
  });

  final RelayService relayService;
  final List<String> relays;
  final String? pubkey;
  final bool loadImages;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<NostrEvent> _events = const [];
  Map<String, ProfileMetadata> _profiles = const {};
  bool _loading = false;
  bool _failed = false;

  Future<void> _load() async {
    final pubkey = widget.pubkey;
    if (pubkey == null || widget.relays.isEmpty) return;

    setState(() {
      _loading = true;
      _failed = false;
    });

    final query = await widget.relayService.queryEvents(
      {
        'kinds': [1, 3, 6, 7, 9735, 1018],
        '#p': [pubkey],
        'limit': 100,
      },
      widget.relays,
    );

    final events = query.events
        .where((event) => event.pubkey != pubkey)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final profiles = <String, ProfileMetadata>{};
    final authors = events.map((event) => event.pubkey).toSet().take(50);
    if (authors.isNotEmpty) {
      final metadata = await widget.relayService.queryEvents(
        {
          'kinds': [0],
          'authors': authors.toList(),
        },
        widget.relays,
      );
      for (final event in metadata.events) {
        final profile = ProfileMetadata.fromKind0(event);
        if (profile != null) profiles[profile.pubkey] = profile;
      }
    }

    if (!mounted) return;
    setState(() {
      _events = events;
      _profiles = profiles;
      _loading = false;
      _failed = !query.reachedRelay;
    });
  }

  String _label(NostrEvent event) {
    return switch (event.kind) {
      1 when event.tags.any((tag) => tag.isNotEmpty && tag.first == 'q') =>
        'quoted you',
      1 when event.tags.any((tag) => tag.isNotEmpty && tag.first == 'e') =>
        'replied to you',
      1 => 'mentioned you',
      3 => 'followed you',
      6 => 'reposted you',
      7 => 'liked you',
      1018 => 'voted on your poll',
      9735 => 'zapped you ${parseZapReceiptAmountMsats(event) ~/ 1000} sats',
      _ => 'interacted with you',
    };
  }

  String? _targetId(NostrEvent event) {
    for (final tag in event.tags.reversed) {
      if (tag.length >= 2 && tag.first == 'e') return tag[1];
    }
    return null;
  }

  LiveSubscription? _live;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
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
      filter: notificationLiveFilter(me),
      onEvent: (_, __) => _scheduleReload(),
    )..start();
  }

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

  void _open(NostrEvent event) {
    final interactions = InteractionsScope.of(context);
    if (interactions == null) return;

    if (event.kind == 3) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserProfilePage(
            pubkey: event.pubkey,
            interactions: interactions,
            loadImages: widget.loadImages,
          ),
        ),
      );
      return;
    }

    final target = _targetId(event);
    if (target == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadPage(
          parent: event.kind == 1 ? event : event,
          parentProfile: _profiles[event.pubkey],
          interactions: interactions,
          loadImages: widget.loadImages,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pubkey == null) {
      return const Center(child: Text('Connect a key to see notifications.'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Notifications observed on your selected relays.',
                ),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
                label: Text(_loading ? 'Loading…' : 'Load'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _failed
              ? const Center(child: Text('No relay responded.'))
              : ListView.separated(
                  itemCount: _events.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final event = _events[index];
                    final profile = _profiles[event.pubkey];
                    final name =
                        profile?.bestName ?? shortNpub(event.authorNpub);
                    return ListTile(
                      leading: MolStrAvatar(
                        name: name,
                        picture: profile?.picture,
                        loadImages: widget.loadImages,
                      ),
                      title: Text('$name ${_label(event)}'),
                      subtitle: Text(formatTimestamp(event.createdAt)),
                      onTap: () => _open(event),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
