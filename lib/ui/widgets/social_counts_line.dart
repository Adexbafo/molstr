import 'package:flutter/material.dart';

import '../../core/nostr/relay_service.dart';
import '../../core/nostr/social_stats.dart';

class SocialCountsLine extends StatefulWidget {
  const SocialCountsLine({
    super.key,
    required this.pubkey,
    required this.relayService,
    required this.relays,
  });

  final String pubkey;
  final RelayService relayService;
  final List<String> relays;

  @override
  State<SocialCountsLine> createState() => _SocialCountsLineState();
}

class _SocialCountsLineState extends State<SocialCountsLine> {
  SocialStats? _stats;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final stats = await loadSocialStats(
      relayService: widget.relayService,
      pubkey: widget.pubkey,
      relays: widget.relays,
    );
    if (mounted) setState(() => _stats = stats);
  }

  String _count(int? value) => value == null ? 'unavailable' : '$value';

  @override
  Widget build(BuildContext context) {
    if (_stats == null) return const Text('Loading social counts…');
    return Text(
      'Following ${_count(_stats!.following)} · '
      'Followers ${_count(_stats!.followers)}',
    );
  }
}
