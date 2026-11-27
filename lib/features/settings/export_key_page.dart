import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/nostr/identity_service.dart';
import '../../core/nostr/nip19.dart';

const _secureChannel = MethodChannel('com.rizful.molstr/secure');

class ExportKeyPage extends StatefulWidget {
  const ExportKeyPage({super.key, required this.identityService});

  final IdentityService identityService;

  @override
  State<ExportKeyPage> createState() => _ExportKeyPageState();
}

class _ExportKeyPageState extends State<ExportKeyPage> {
  bool _loading = true;
  bool _hasLocalKey = false;
  String? _npub;
  bool _revealed = false;
  String? _nsec;
  bool _acknowledged = false;
  final _confirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final identity = await widget.identityService.currentIdentity();
    final nsecHex = await widget.identityService.currentNsecHex();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _hasLocalKey = nsecHex != null && identity != null;
      _npub = identity?.npub;
    });
  }

  @override
  void dispose() {
    _setScreenshotBlock(false);
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _setScreenshotBlock(bool on) async {
    if (!Platform.isAndroid)
      return; // desktop has no FLAG_SECURE equivalent here
    try {
      await _secureChannel.invokeMethod(
        on ? 'blockScreenshots' : 'allowScreenshots',
      );
    } catch (_) {
      // Older Android or missing handler: continue without the flag.
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _reveal() async {
    if (_confirmController.text.trim() != 'EXPORT') {
      _message('Type EXPORT exactly to continue.');
      return;
    }
    final nsecHex = await widget.identityService.currentNsecHex();
    if (nsecHex == null || !mounted) return;

    await _setScreenshotBlock(true);
    // The key lives only in this local variable while the screen is shown.
    setState(() {
      _nsec = Nip19.nsecFromHex(nsecHex);
      _revealed = true;
      _acknowledged = false;
    });
  }

  Future<void> _hide() async {
    await _setScreenshotBlock(false);
    if (!mounted) return;
    setState(() {
      _nsec = null;
      _revealed = false;
      _acknowledged = false;
      _confirmController.clear();
    });
  }

  Future<void> _copy() async {
    final nsec = _nsec;
    if (nsec == null) return;
    await Clipboard.setData(ClipboardData(text: nsec));
    _message('Private key copied. Store it somewhere safe.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Export key')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasLocalKey) {
      return Scaffold(
        appBar: AppBar(title: const Text('Export key')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No local key is stored on this device.\n\n'
              'Amber and remote-signer accounts keep their key outside MolStr, '
              'so there is nothing to export here.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (!_revealed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Export key')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 56, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Reveal your private key',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Your nsec is the master key to ${_npub ?? 'this account'}. '
                  'Anyone who has it can post, delete, and spend as you. '
                  'MolStr will show it once, block screenshots on Android, '
                  'and never log it.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _confirmController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Type EXPORT to reveal',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _reveal,
                  icon: const Icon(Icons.visibility),
                  label: const Text('Show private key'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Private key')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QrImageView(
                  data: _nsec!,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              SelectableText(_nsec!, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copy,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy nsec'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _hide,
                      icon: const Icon(Icons.visibility_off),
                      label: const Text('Hide key'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _acknowledged,
                onChanged: (v) => setState(() => _acknowledged = v ?? false),
                title: const Text('I have saved this key in a safe place.'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed:
                    _acknowledged ? () => Navigator.of(context).pop() : null,
                child: const Text('Done'),
              ),
              const SizedBox(height: 12),
              const Text(
                'MolStr stores the key only in device secure storage and never '
                'prints it to logs. Losing it means losing the account.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
