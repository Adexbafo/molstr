import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/nostr/identity_service.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/relay_service.dart';

class ProfileEditorPage extends StatefulWidget {
  const ProfileEditorPage({
    super.key,
    required this.identityService,
    required this.relayService,
    required this.relays,
    required this.current,
  });

  final IdentityService identityService;
  final RelayService relayService;
  final List<String> relays;
  final ProfileMetadata? current;

  @override
  State<ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends State<ProfileEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _about;
  late final TextEditingController _picture;
  late final TextEditingController _banner;
  late final TextEditingController _nip05;
  late final TextEditingController _lud16;
  late final TextEditingController _monero;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    // If the name box shows your npub, just overwrite it.
    _name = TextEditingController(text: c?.bestName ?? '');
    _about = TextEditingController(text: c?.about ?? '');
    _picture = TextEditingController(text: c?.picture ?? '');
    _banner = TextEditingController(text: c?.banner ?? '');
    _nip05 = TextEditingController(text: c?.nip05 ?? '');
    _lud16 = TextEditingController(text: c?.lud16 ?? '');
    _monero = TextEditingController(text: c?.moneroAddress ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    _picture.dispose();
    _banner.dispose();
    _nip05.dispose();
    _lud16.dispose();
    _monero.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final name = _name.text.trim();
    final content = jsonEncode({
      'name': name,
      'display_name': name,
      'about': _about.text.trim(),
      'picture': _picture.text.trim(),
      'banner': _banner.text.trim(),
      'nip05': _nip05.text.trim(),
      'lud16': _lud16.text.trim(),
      'monero_address': _monero.text.trim(),
    });

    try {
      final event =
          await widget.identityService.signEvent(kind: 0, content: content);
      final results =
          await widget.relayService.publishEvent(event, widget.relays);
      if (!mounted) return;
      final okCount = results.values.where((v) => v == 'ok').length;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(okCount > 0
              ? 'Profile published to $okCount of ${results.length} relays'
              : 'No relay accepted the update'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in results.entries)
                Text('${Uri.tryParse(e.key)?.host ?? e.key}: ${e.value}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(okCount > 0);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not sign or publish the profile.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = (
      name: '',
      items: <(String, TextEditingController, String)>[
        ('Display name', _name, 'e.g. MolStr'),
        ('About', _about, 'A short bio'),
        ('Picture URL', _picture, 'https://…/avatar.png'),
        ('Banner URL', _banner, 'https://…/banner.png'),
        ('NIP-05 identifier', _nip05, 'molstr@rizful.com'),
        ('Lightning address (lud16)', _lud16, 'molstr@rizful.com'),
        ('Monero address', _monero, '4… or 8…'),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (label, controller, hint) in fields.items) ...[
            TextField(
              controller: controller,
              enabled: !_saving,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Publishes a public kind-0 metadata event to: '
                '${widget.relays.join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.publish),
            label: Text(_saving ? 'Publishing…' : 'Save profile'),
          ),
        ],
      ),
    );
  }
}