import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/nostr/identity_service.dart';
import '../../core/nostr/relay_service.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({
    super.key,
    required this.identityService,
    required this.relayService,
    required this.relays,
    required this.preferences,
  });

  final IdentityService identityService;
  final RelayService relayService;
  final List<String> relays;
  final SharedPreferences preferences;

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  Identity? _identity;
  bool _testingRelays = false;
  final Map<String, String> _relayLatency = {};

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    final id = await widget.identityService.currentIdentity();
    if (mounted) setState(() => _identity = id);
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _clearImageCache() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    _message('Image memory cache cleared.');
  }

  Future<void> _clearNip05Cache() async {
    final keys =
        widget.preferences.getKeys().where((k) => k.startsWith('nip05'));
    var count = 0;
    for (final k in keys) {
      await widget.preferences.remove(k);
      count++;
    }
    _message('Cleared $count cached NIP-05 verification entries.');
  }

  Future<void> _clearLocalInteractions() async {
    await widget.preferences.remove('interactions.liked');
    await widget.preferences.remove('interactions.reposted');
    _message('Local like and repost markers cleared.');
  }

  Future<void> _testRelays() async {
    if (widget.relays.isEmpty) {
      _message('No relays configured.');
      return;
    }
    setState(() {
      _testingRelays = true;
      _relayLatency.clear();
    });

    for (final relay in widget.relays) {
      final stopwatch = Stopwatch()..start();
      try {
        final channel = WebSocketChannel.connect(Uri.parse(relay));
        await channel.ready.timeout(const Duration(seconds: 4));
        stopwatch.stop();
        unawaited(channel.sink.close());
        if (mounted) {
          setState(() =>
              _relayLatency[relay] = '${stopwatch.elapsedMilliseconds} ms');
        }
      } catch (e) {
        stopwatch.stop();
        if (mounted) {
          setState(() => _relayLatency[relay] = 'Failed / Timed out');
        }
      }
    }

    if (mounted) setState(() => _testingRelays = false);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Tools & Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Cache Management', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('Clear Image Cache'),
                  subtitle: const Text(
                      'Frees memory used by avatars and note previews'),
                  trailing: OutlinedButton(
                    onPressed: _clearImageCache,
                    child: const Text('Clear'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: const Text('Clear NIP-05 Cache'),
                  subtitle: const Text(
                      'Forces fresh domain checks for verified badges'),
                  trailing: OutlinedButton(
                    onPressed: _clearNip05Cache,
                    child: const Text('Clear'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: const Text('Reset Local Interaction History'),
                  subtitle: const Text(
                      'Clears local "Liked" and "Reposted" highlighted state'),
                  trailing: OutlinedButton(
                    onPressed: _clearLocalInteractions,
                    child: const Text('Reset'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Relay Latency & Diagnostics', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Configured Relays (${widget.relays.length})'),
                      FilledButton.icon(
                        onPressed: _testingRelays ? null : _testRelays,
                        icon: _testingRelays
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.speed, size: 16),
                        label:
                            Text(_testingRelays ? 'Testing…' : 'Ping Relays'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (widget.relays.isEmpty)
                    const Text('No relays configured.')
                  else
                    for (final r in widget.relays)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(child: SelectableText(r)),
                            Text(
                              _relayLatency[r] ?? 'Not tested',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _relayLatency[r]?.contains('ms') == true
                                    ? Colors.green
                                    : (_relayLatency[r]?.contains('Failed') ==
                                            true
                                        ? Colors.red
                                        : null),
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Identity Diagnostics', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _identity == null
                  ? const Text('No local Nostr identity connected.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Public Key (npub)',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        SelectableText(_identity!.npub,
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 12),
                        const Text('Public Key (Hex)',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        SelectableText(_identity!.pubkey,
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.lock_outline,
                                size: 16, color: Colors.green),
                            const SizedBox(width: 6),
                            const Text(
                                'Private key secured in OS Keyring / Secure Storage'),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
