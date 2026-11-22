import 'package:flutter/material.dart';

import '../../core/nostr/identity_service.dart';

class ImportKeyPage extends StatefulWidget {
  const ImportKeyPage({super.key});

  @override
  State<ImportKeyPage> createState() => _ImportKeyPageState();
}

class _ImportKeyPageState extends State<ImportKeyPage> {
  final _service = IdentityService();
  final _controller = TextEditingController();

  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _controller.text.trim();

    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an nsec key.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    try {
      await _service.saveIdentity(value);

      if (!mounted) return;
      Navigator.of(context).pop<bool>(true);
    } catch (_) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Invalid nsec, or secure storage is unavailable.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import key')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Import your Nostr identity',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Paste your nsec key. MolStr stores it in the operating system '
            'secure storage. Never share your nsec with anyone.',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            minLines: 1,
            maxLines: _obscure ? 1 : 5,
            decoration: InputDecoration(
              labelText: 'nsec key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show key' : 'Hide key',
                onPressed: () {
                  setState(() => _obscure = !_obscure);
                },
                icon: Icon(
                  _obscure ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(_saving ? 'Importing...' : 'Import key'),
          ),
        ],
      ),
    );
  }
}