import 'package:shared_preferences/shared_preferences.dart';

import '../../core/nostr/identity_service.dart';
import '../../core/nostr/relay_service.dart';
import '../../core/nostr/user_relays.dart';
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
    required this.onOpenTools,
    required this.onOpenDmRelays,
    required this.identityService,
    required this.relayService,
    required this.preferences,
    required this.selectedRelays,
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
  final VoidCallback? onOpenTools;
  final VoidCallback? onOpenDmRelays;
  final IdentityService identityService;
  final RelayService relayService;
  final SharedPreferences preferences;
  final List<String> selectedRelays;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _GlobalRelaysPage extends StatefulWidget {
  const _GlobalRelaysPage({
    required this.service,
    required this.selectedRelays,
  });

  final UserRelayService service;
  final List<String> selectedRelays;

  @override
  State<_GlobalRelaysPage> createState() => _GlobalRelaysPageState();
}

class _GlobalRelaysPageState extends State<_GlobalRelaysPage> {
  late List<String> _relays;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _relays = List<String>.from(widget.service.loadGlobalRelays());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.service.saveGlobalRelays(_relays);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Global relays saved.')),
    );
  }

  void _add() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;
    try {
      final normalized = RelayService.normalizeRelayUrl(raw);
      setState(() {
        if (!_relays.contains(normalized)) _relays.add(normalized);
        _controller.clear();
      });
    } on FormatException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Global relays')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Add wss:// relay',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _add, child: const Text('Add')),
            ],
          ),
          const SizedBox(height: 16),
          if (_relays.isEmpty)
            const Text('No global relays yet.')
          else
            for (final relay in _relays)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text(relay),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _relays.remove(relay)),
                  ),
                ),
              ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _PublishOwnRelayListPage extends StatefulWidget {
  const _PublishOwnRelayListPage({
    required this.service,
    required this.selectedRelays,
  });

  final UserRelayService service;
  final List<String> selectedRelays;

  @override
  State<_PublishOwnRelayListPage> createState() =>
      _PublishOwnRelayListPageState();
}

class _PublishOwnRelayListPageState extends State<_PublishOwnRelayListPage> {
  final Set<String> _read = {};
  final Set<String> _write = {};
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    _read.addAll(widget.selectedRelays);
    _write.addAll(widget.selectedRelays);
  }

  Future<void> _publish() async {
    if (_read.isEmpty && _write.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one relay.')),
      );
      return;
    }

    setState(() => _publishing = true);
    try {
      final results = await widget.service.publishOwnRelayList(
        readRelays: _read.toList(),
        writeRelays: _write.toList(),
        publishRelays: widget.selectedRelays,
      );
      if (!mounted) return;
      final ok = results.values.where((v) => v == 'ok').length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok > 0
                ? 'Relay list published to $ok of ${results.length} relays.'
                : 'No relay accepted the list.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Publish NIP-65 relay list')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final relay in widget.selectedRelays)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(relay),
                    Row(
                      children: [
                        FilterChip(
                          label: const Text('Read'),
                          selected: _read.contains(relay),
                          onSelected: _publishing
                              ? null
                              : (value) => setState(() {
                                    if (value) {
                                      _read.add(relay);
                                    } else {
                                      _read.remove(relay);
                                    }
                                  }),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Write'),
                          selected: _write.contains(relay),
                          onSelected: _publishing
                              ? null
                              : (value) => setState(() {
                                    if (value) {
                                      _write.add(relay);
                                    } else {
                                      _write.remove(relay);
                                    }
                                  }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _publishing ? null : _publish,
            icon: _publishing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.publish),
            label: Text(_publishing ? 'Publishing…' : 'Publish'),
          ),
        ],
      ),
    );
  }
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
            const Divider(height: 48),
            Text('Global relays', style: textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Fallback relays used when a specific user has not published a '
              'NIP-65 relay list. Edit here; they are not used for your own '
              'live subscriptions.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.public_outlined),
                title: const Text('Edit global relays'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _GlobalRelaysPage(
                        service: UserRelayService(
                          relayService: widget.relayService,
                          identityService: widget.identityService,
                          preferences: widget.preferences,
                        ),
                        selectedRelays: widget.selectedRelays,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: const Text('Publish NIP-65 relay list'),
                subtitle: const Text(
                  'Lets other clients know where to send you events and where '
                  'you publish.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _PublishOwnRelayListPage(
                        service: UserRelayService(
                          relayService: widget.relayService,
                          identityService: widget.identityService,
                          preferences: widget.preferences,
                        ),
                        selectedRelays: widget.selectedRelays,
                      ),
                    ),
                  );
                },
              ),
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
        const Divider(height: 48),
        Text('Diagnostics', style: textTheme.headlineSmall),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.build_circle_outlined),
            title: const Text('Tools & Storage Diagnostics'),
            subtitle: const Text(
                'Manage image/NIP-05 caches and test relay response speeds'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onOpenTools,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('DM relays (NIP-17)'),
            subtitle: const Text(
              'Choose where others send your private messages',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onOpenDmRelays,
          ),
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
