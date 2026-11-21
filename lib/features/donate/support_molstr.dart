import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../ui/theme/app_theme.dart';

const molstrLightning = 'MolStr@rizful.com';
const molstrMonero =
    '47MejNNfkM939AbAsaNMWX3Scf87G5LzLPoFfaDsV8oiLhyj3CrMxGDebVKN6JLz38aJJjucDr9fBUZAMtVknmGPGUZM6LX';
const molstrGithub = 'https://github.com/Adexbafo/molstr';

class SupportMolStrPage extends StatelessWidget {
  const SupportMolStrPage({super.key});

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support MolStr')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'MolStr is 100% free and open-source. Donations go directly to development with no intermediaries or platforms taking fees.',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 24),

          // Bitcoin Lightning Section
          Card(
            color: MolStrColors.cardDark,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('⚡ Bitcoin Lightning',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: QrImageView(
                        data: molstrLightning,
                        version: QrVersions.auto,
                        size: 160,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: SelectableText(
                      molstrLightning,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _copy(context, molstrLightning),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy Lightning Address'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Monero Section
          Card(
            color: MolStrColors.cardDark,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🔒 Monero (XMR)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: QrImageView(
                        data: 'monero:$molstrMonero',
                        version: QrVersions.auto,
                        size: 160,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    molstrMonero,
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        onPressed: () => _copy(context, molstrMonero),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy'),
                      ),
                      TextButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(
                              'monero:$molstrMonero?tx_description=MolStr%20Donation'),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Open Wallet'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // GitHub Link
          Center(
            child: TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(molstrGithub),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.star, color: Colors.amber),
              label: const Text('Star MolStr on GitHub'),
            ),
          ),
        ],
      ),
    );
  }
}