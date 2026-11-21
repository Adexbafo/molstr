import 'package:flutter/material.dart';
import '../../ui/theme/app_theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.preset,
    required this.onPresetChanged,
  });

  final MolStrPreset preset;
  final Future<void> Function(MolStrPreset) onPresetChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Appearance',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Choose how MolStr looks on this device.'),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: DropdownButtonFormField<MolStrPreset>(
              value: preset,
              decoration: const InputDecoration(
                labelText: 'Theme',
                border: OutlineInputBorder(),
              ),
              items: MolStrPreset.values
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(item.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) async {
                if (value == null) return;

                try {
                  await onPresetChanged(value);
                } catch (_) {
                  if (!context.mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Theme applied, but the preference could not be saved.',
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Theme preview',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Notes, profiles, navigation, and settings use your chosen '
                  'theme. Your selection is stored locally.',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('This is a theme preview.')),
                    );
                  },
                  icon: const Icon(Icons.palette_outlined),
                  label: const Text('Preview button'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Fonts',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Currently using default typography. Bundled font choices will be '
          'added next, without runtime font downloads.',
        ),
      ],
    );
  }
}