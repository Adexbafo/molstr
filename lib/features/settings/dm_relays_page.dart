import 'package:flutter/material.dart';

import '../../core/nostr/identity_service.dart';
import '../../core/nostr/relay_service.dart';
import '../messages/message_service.dart';

class DmRelaysPage extends StatefulWidget {
  const DmRelaysPage({
    super.key,
    required this.identityService,
    required this.relayService,
    required this.selectedRelays,
  });

  final IdentityService identityService;
  final RelayService relayService;
  final List<String> selectedRelays;

  @override
  State<DmRelaysPage> createState() => _DmRelaysPageState();
}

class _DmRelaysPageState extends State<DmRelaysPage> {
  late final MessageService _service;
  final _customController = TextEditingController();
  final Set<String> _chosen = {};
  List<String> _published = const [];
  bool _loading = true;
  bool _publishing = false;
  String? _resultText;

  @override
  void initState() {
    super.initState();
    _service = MessageService(
      identityService: widget.identityService,
      relayService: widget.relayService,
    );
    _load();
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = await widget.identityService.currentIdentity();
    if (me == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final current = await _service.fetchDmRelayList(
      me.pubkey,
      widget.selectedRelays,
    );
    if (!mounted) return;
    setState(() {
      _published = current;
      _chosen.clear();
      if (current.isNotEmpty) {
        _chosen.addAll(current);
      } else {
        _chosen.addAll(widget.selectedRelays);
      }
      _loading = false;
    });
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _addCustom() {
    final value = _customController.text.trim();
    if (value.isEmpty) return;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'wss' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      _message('Use a wss:// relay URL without credentials.');
      return;
    }
    setState(() {
      _chosen.add(value);
      _customController.clear();
    });
  }

  Future<void> _publish() async {
    if (_chosen.isEmpty) {
      _message('Choose at least one DM relay.');
      return;
    }
    setState(() {
      _publishing = true;
      _resultText = null;
    });
    try {
      final result = await _service.publishDmRelayList(
        dmRelays: _chosen.toList(),
        publishRelays: widget.selectedRelays,
      );
      if (!mounted) return;
      final ok = result.values.where((v) => v == 'ok').length;
      setState(() {
        _resultText = ok > 0
            ? 'Published to $ok of ${result.length} relays.'
            : 'No relay accepted the list.';
        if (ok > 0) _published = _chosen.toList();
      });
      _message(
        ok > 0 ? 'DM relay list published.' : 'No relay accepted the list.',
      );
    } catch (e) {
      _message(
        'Could not publish: ${e.toString().replaceFirst('Exception: ', '')}',
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('DM relays (NIP-17)')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('DM relays (NIP-17)')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'This public list tells other clients which relays to send '
                'your private messages to. It is not private. Publishing '
                'replaces your previous list.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Currently published', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_published.isEmpty)
            const Text(
              'No list published yet. MolStr currently falls back to your '
              'selected relays.',
            )
          else
            for (final relay in _published)
              ListTile(
                dense: true,
                leading: const Icon(Icons.dns_outlined, size: 18),
                title: Text(relay),
              ),
          const Divider(height: 32),
          Text('Choose DM relays', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final relay in widget.selectedRelays)
            CheckboxListTile(
              title: Text(relay),
              value: _chosen.contains(relay),
              onChanged: _publishing
                  ? null
                  : (value) => setState(() {
                        if (value == true) {
                          _chosen.add(relay);
                        } else {
                          _chosen.remove(relay);
                        }
                      }),
            ),
          for (final relay
              in _chosen.where((e) => !widget.selectedRelays.contains(e)))
            CheckboxListTile(
              title: Text(relay),
              value: true,
              onChanged: _publishing
                  ? null
                  : (value) => setState(() {
                        if (value != true) _chosen.remove(relay);
                      }),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customController,
                  enabled: !_publishing,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Add wss:// relay',
                    hintText: 'wss://relay.example.com',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _publishing ? null : _addCustom,
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _publishing ? null : _publish,
            icon: _publishing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.publish),
            label: Text(_publishing ? 'Publishing…' : 'Publish DM relay list'),
          ),
          if (_resultText != null) ...[
            const SizedBox(height: 12),
            Text(_resultText!),
          ],
        ],
      ),
    );
  }
}
