import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/nostr/relay_settings.dart';

class RelaySettingsTile extends StatelessWidget {
  const RelaySettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.dns_outlined),
      title: const Text('Relays'),
      subtitle: const Text('Manage read and write relays'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const RelaysPage()),
      ),
    );
  }
}

class RelaysPage extends StatefulWidget {
  const RelaysPage({super.key});

  @override
  State<RelaysPage> createState() => _RelaysPageState();
}

class _RelaysPageState extends State<RelaysPage> {
  final _url = TextEditingController();
  RelaySettingsStore? _store;
  List<RelayConfig> _relays = [];
  bool _loadFailed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final store = RelaySettingsStore(await SharedPreferences.getInstance());
      final relays = store.load();
      if (!mounted) return;
      setState(() {
        _store = store;
        _relays = relays;
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<bool> _save(List<RelayConfig> next) async {
    final store = _store;
    if (store == null || _saving) return false;

    setState(() => _saving = true);
    try {
      await store.save(next);
      if (!mounted) return false;
      _relays = next;
      return true;
    } catch (_) {
      if (mounted) _showMessage('Could not save relay settings.');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _add() async {
    final String url;
    try {
      url = normalizeRelayUrl(_url.text);
    } on FormatException catch (error) {
      _showMessage(error.message);
      return;
    }

    if (_relays.any((relay) => relay.url == url)) {
      _showMessage('This relay is already on your list.');
      return;
    }

    final saved = await _save([..._relays, RelayConfig(url: url)]);
    if (saved && mounted) _url.clear();
  }

  Future<bool> _update(RelayConfig updated) => _save([
        for (final relay in _relays)
          if (relay.url == updated.url) updated else relay,
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Relays')),
      body: _store == null
          ? Center(
              child: _loadFailed
                  ? const Text('Could not load saved relay settings.')
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Changes are saved on this device. Adding a relay here '
                  'does not connect to it yet.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _url,
                  enabled: !_saving,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Relay URL',
                    hintText: 'wss://relay.damus.io',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _add(),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _saving ? null : _add,
                    child: const Text('Add relay'),
                  ),
                ),
                const SizedBox(height: 16),
                if (_relays.isEmpty) const Text('No relays configured.'),
                for (final relay in _relays)
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          title: Text(relay.url),
                          trailing: IconButton(
                            tooltip: 'Remove relay',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _saving
                                ? null
                                : () => _save(
                                      _relays
                                          .where((r) => r.url != relay.url)
                                          .toList(),
                                    ),
                          ),
                        ),
                        SwitchListTile(
                          title: const Text('Read'),
                          value: relay.read,
                          onChanged: _saving
                              ? null
                              : (value) => _update(relay.copyWith(read: value)),
                        ),
                        SwitchListTile(
                          title: const Text('Write'),
                          value: relay.write,
                          onChanged: _saving
                              ? null
                              : (value) => _update(relay.copyWith(write: value)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}