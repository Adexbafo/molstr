import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/nostr/identity_service.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/relay_service.dart';
import '../../core/payments/monero.dart';

class MoneroWalletSection extends StatefulWidget {
  const MoneroWalletSection({
    super.key,
    required this.identityService,
    required this.relayService,
    required this.relays,
  });

  final IdentityService identityService;
  final RelayService relayService;
  final List<String> relays;

  @override
  State<MoneroWalletSection> createState() => _MoneroWalletSectionState();
}

class _MoneroWalletSectionState extends State<MoneroWalletSection> {
  String? _address;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    final me = await widget.identityService.currentIdentity();
    if (!mounted) return;
    if (me == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final query = await widget.relayService.queryEvents(
      {
        'kinds': [0],
        'authors': [me.pubkey],
        'limit': 1
      },
      widget.relays,
    );

    String? address;
    if (query.reachedRelay && query.events.isNotEmpty) {
      final profile = ProfileMetadata.fromKind0(query.events.first);
      address = profile?.moneroAddress;
    }

    if (mounted) {
      setState(() {
        _address = address;
        _loading = false;
      });
    }
  }

  Future<void> _edit() async {
    final me = await widget.identityService.currentIdentity();
    if (!mounted) return;
    if (me == null) {
      _message('Connect a key in Profile to save a Monero address.');
      return;
    }

    final controller = TextEditingController(text: _address ?? '');
    final newAddress = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Monero receiving address'),
        content: TextField(
          controller: controller,
          maxLines: 1,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Monero address',
            hintText: '4... or 8...',
            helperText: '95 or 106 characters, starts with 4 or 8',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newAddress == null || newAddress.isEmpty) return;

    if (!isValidMoneroAddress(newAddress)) {
      _message(
        'Invalid Monero address. Must be 95 or 106 characters, '
        'starting with 4 or 8.',
      );
      return;
    }

    // Merge with existing kind 0 so other profile fields survive.
    String content = jsonEncode({'monero_address': newAddress});
    final query = await widget.relayService.queryEvents(
      {
        'kinds': [0],
        'authors': [me.pubkey],
        'limit': 1
      },
      widget.relays,
    );
    if (query.reachedRelay && query.events.isNotEmpty) {
      try {
        final decoded = jsonDecode(query.events.first.content);
        if (decoded is Map<String, dynamic>) {
          decoded['monero_address'] = newAddress;
          content = jsonEncode(decoded);
        }
      } catch (_) {
        // A corrupt kind-0 is replaced by the new content.
      }
    }

    try {
      final event = await widget.identityService.signEvent(
        kind: 0,
        content: content,
      );
      final results = await widget.relayService.publishEvent(
        event,
        widget.relays,
      );
      final ok = results.values.where((v) => v == 'ok').length;
      if (!mounted) return;
      setState(() => _address = newAddress);
      _message(
        ok > 0
            ? 'Monero address saved to $ok relay(s).'
            : 'No relay accepted the update.',
      );
    } catch (_) {
      _message('Could not publish. Is a key connected?');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(
          Icons.lock_outline,
          size: 56,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Monero',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Show a Monero address so others can tip you privately. '
          'MolStr does not hold a seed, run a node, or track payments.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (_address != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Receiving address',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: QrImageView(
                      data: _address!,
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    _address!,
                    style: const TextStyle(fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _address!),
                          );
                          _message('Address copied.');
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _edit,
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('No Monero address set.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _edit,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Monero address'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Monero payments are private. When someone tips you, MolStr '
              'opens their external Monero wallet with a payment request. '
              'MolStr never confirms the payment — only the sender\'s wallet '
              'and the Monero blockchain know that.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}
