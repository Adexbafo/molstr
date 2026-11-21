import 'package:flutter/material.dart';
import '../../ui/theme/app_theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.preset,
    required this.font,
    required this.onPresetChanged,
    required this.onFontChanged,
  });

  final MolStrPreset preset;
  final MolStrFont font;
  final Future<void> Function(MolStrPreset) onPresetChanged;
  final Future<void> Function(MolStrFont) onFontChanged;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Applied, but the setting could not be saved.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Appearance', style: textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Colors and fonts are saved on this device only.'),
        const SizedBox(height: 24),

        Text('Color theme', style: textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final option in MolStrPreset.values)
              ChoiceChip(
                label: Text(option.label),
                selected: preset == option,
                onSelected: (_) =>
                    _run(context, () => onPresetChanged(option)),
              ),
          ],
        ),
        const SizedBox(height: 28),

        Text('Font', style: textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final option in MolStrFont.values)
              ChoiceChip(
                label: Text(
                  option.label,
                  style: TextStyle(fontFamily: option.family),
                ),
                selected: font == option,
                onSelected: (_) => _run(context, () => onFontChanged(option)),
              ),
          ],
        ),
        const SizedBox(height: 28),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Preview', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'MolStr shares notes, zaps, and games without tracking.',
                ),
                const SizedBox(height: 8),
                Text(
                  'npub1example · 2 min ago',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Fonts are bundled with the app. MolStr does not download fonts '
          'while you use it.',
        ),
      ],
    );
  }
}