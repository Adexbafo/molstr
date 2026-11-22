import 'package:flutter/material.dart';
import '../../ui/theme/app_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.preset,
    required this.font,
    required this.onPresetChanged,
    required this.onFontChanged,
    required this.relays,
    required this.onAddRelay,
    required this.onRemoveRelay,
    required this.onResetRelays,
    required this.loadImages,
    required this.onLoadImagesChanged,
  });

  final MolStrPreset preset;
  final MolStrFont font;
  final Future<void> Function(MolStrPreset) onPresetChanged;
  final Future<void> Function(MolStrFont) onFontChanged;
  final List<String> relays;
  final Future<void> Function(String url) onAddRelay;
  final Future<void> Function(String url) onRemoveRelay;
  final Future<void> Function() onResetRelays;
  final bool loadImages;
  final Future<void> Function(bool) onLoadImagesChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _relayController = TextEditingController();

  @override
  void dispose() {
    _relayController.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool clearRelayInput = false,
  }) async {
    try {
      await action();
      if (clearRelayInput) {
        _relayController.clear();
      }
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save setting on this device.'),
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
                selected: widget.preset == option,
                onSelected: (_) => _run(() => widget.onPresetChanged(option)),
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
                selected: widget.font == option,
                onSelected: (_) => _run(() => widget.onFontChanged(option)),
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
        const SizedBox(height: 12),
        const Text(
          'Fonts are bundled with the app. MolStr does not download fonts '
          'while you use it.',
        ),
        const Divider(height: 48),
        Text('Relays', style: textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Choose which Nostr relays MolStr contacts. Remote relays must use '
          'encrypted wss:// connections.',
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _relayController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Add relay URL',
                    hintText: 'wss://relay.example.com',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) => _run(
                    () => widget.onAddRelay(value),
                    clearRelayInput: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _run(
                  () => widget.onAddRelay(_relayController.text),
                  clearRelayInput: true,
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (widget.relays.isEmpty)
          const Text('No relays configured.')
        else
          for (final relay in widget.relays)
            Card(
              child: ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(relay),
                trailing: IconButton(
                  tooltip: 'Remove relay',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _run(() => widget.onRemoveRelay(relay)),
                ),
              ),
            ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _run(widget.onResetRelays),
            icon: const Icon(Icons.restore),
            label: const Text('Restore starter relays'),
          ),
        ),
        const Divider(height: 48),
        Text('Privacy', style: textTheme.headlineSmall),
        const SizedBox(height: 8),
        SwitchListTile(
          value: widget.loadImages,
          onChanged: (value) => _run(() => widget.onLoadImagesChanged(value)),
          title: const Text('Load remote images'),
          subtitle: const Text(
            'Avatars, banners and note images are fetched from the hosts '
            'storing them. They will see your IP address.',
          ),
        ),
      ],
    );
  }
}
