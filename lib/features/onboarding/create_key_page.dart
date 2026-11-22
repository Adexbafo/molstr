import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/nostr/identity_service.dart';

class CreateKeyPage extends StatefulWidget {
  const CreateKeyPage({super.key});

  @override
  State<CreateKeyPage> createState() => _CreateKeyPageState();
}

class _CreateKeyPageState extends State<CreateKeyPage> {
  final _service = IdentityService();

  late final GeneratedIdentity _generated;
  String? _error;

  bool _confirmed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    try {
      _generated = _service.generateIdentity();
    } catch (_) {
      _error = 'Could not generate a key on this device.';
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(
      ClipboardData(text: _generated.nsec),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Private key copied.')),
    );
  }

  Future<void> _save() async {
    if (!_confirmed) return;

    setState(() => _saving = true);

    try {
      await _service.saveIdentity(_generated.nsec);

      if (!mounted) return;
      Navigator.of(context).pop<bool>(true);
    } catch (_) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save the key to secure storage. Check your desktop '
            'keyring and try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Back up key')),
        body: Center(child: Text(_error!)),
      );
    }

    final npub = _generated.identity.npub;

    return Scaffold(
      appBar: AppBar(title: const Text('Back up your key')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Save this private key now',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'This nsec is your Nostr identity. Anyone who has it can post '
            'and act as you. MolStr will not show it again after you finish '
            'backup.',
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Public key',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(npub),
                  const SizedBox(height: 20),
                  const Text(
                    'Private key',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _generated.nsec,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy private key'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _confirmed,
            onChanged: _saving
                ? null
                : (value) {
                    setState(() => _confirmed = value ?? false);
                  },
            title: const Text(
              'I have saved this private key in a secure place.',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _confirmed && !_saving ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Finish setup'),
          ),
        ],
      ),
    );
  }
}