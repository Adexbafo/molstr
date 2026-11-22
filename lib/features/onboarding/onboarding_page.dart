import 'package:flutter/material.dart';

import 'create_key_page.dart';
import 'import_key_page.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  Future<void> _openCreate(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const CreateKeyPage(),
      ),
    );

    if (saved == true && context.mounted) {
      Navigator.of(context).pop<bool>(true);
    }
  }

  Future<void> _openImport(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const ImportKeyPage(),
      ),
    );

    if (saved == true && context.mounted) {
      Navigator.of(context).pop<bool>(true);
    }
  }

  void _notReady(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Amber support is coming later.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Get started')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Icon(
                Icons.key_outlined,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                'Your identity belongs to you',
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'A Nostr public key identifies your account. Your private '
                'key lets you sign notes and must stay secret. MolStr does '
                'not require an account on a MolStr server.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Before you begin',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Back up a newly created private key safely. '
                        'Anyone with your private key can act as you. '
                        'Relays you connect to can see your IP address '
                        'and the events you request.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _openCreate(context),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Create a new key'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _openImport(context),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Import an existing key'),
              ),
              const SizedBox(height: 8),
              if (Theme.of(context).platform == TargetPlatform.android)
                OutlinedButton.icon(
                  onPressed: () => _notReady(context),
                  icon: const Icon(Icons.phonelink_lock_outlined),
                  label: const Text('Use Amber — coming later'),
                ),
              const SizedBox(height: 16),
              Text(
                'On Linux, iOS, macOS, and Windows, we will also offer a '
                'remote signer. Amber integration is Android-only.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
