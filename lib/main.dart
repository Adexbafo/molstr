import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/nostr/identity_service.dart';
import 'features/donate/support_molstr.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/settings/settings_page.dart';
import 'ui/theme/app_theme.dart';

const _themeKey = 'appearance.theme';
const _fontKey = 'appearance.font';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      child: MolStrApp(preferences: preferences),
    ),
  );
}

T _readEnum<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

String _shortNpub(String npub) {
  if (npub.length <= 24) return npub;
  return '${npub.substring(0, 14)}…${npub.substring(npub.length - 10)}';
}

class MolStrApp extends StatefulWidget {
  const MolStrApp({super.key, required this.preferences});

  final SharedPreferences preferences;

  @override
  State<MolStrApp> createState() => _MolStrAppState();
}

class _MolStrAppState extends State<MolStrApp> {
  late MolStrPreset _preset;
  late MolStrFont _font;

  @override
  void initState() {
    super.initState();

    _preset = _readEnum(
      MolStrPreset.values,
      widget.preferences.getString(_themeKey),
      MolStrPreset.nightInk,
    );

    _font = _readEnum(
      MolStrFont.values,
      widget.preferences.getString(_fontKey),
      MolStrFont.system,
    );
  }

  Future<void> _savePreference(String key, String value) async {
    final saved = await widget.preferences.setString(key, value);
    if (!saved) {
      throw StateError('Could not save $key');
    }
  }

  Future<void> _changePreset(MolStrPreset preset) async {
    setState(() => _preset = preset);
    await _savePreference(_themeKey, preset.name);
  }

  Future<void> _changeFont(MolStrFont font) async {
    setState(() => _font = font);
    await _savePreference(_fontKey, font.name);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MolStr',
      debugShowCheckedModeBanner: false,
      theme: MolStrTheme.forPreset(_preset, _font),
      home: MolStrShell(
        preset: _preset,
        font: _font,
        onPresetChanged: _changePreset,
        onFontChanged: _changeFont,
      ),
    );
  }
}

class MolStrShell extends StatefulWidget {
  const MolStrShell({
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

  @override
  State<MolStrShell> createState() => _MolStrShellState();
}

class _MolStrShellState extends State<MolStrShell> {
  final _identityService = IdentityService();

  int _index = 0;

  Identity? _identity;
  bool _identityLoading = true;
  String? _identityError;

  static const _labels = [
    'Home',
    'Games',
    'Notifications',
    'Wallet',
    'Profile',
    'Settings',
  ];

  static const _icons = [
    Icons.home_outlined,
    Icons.sports_esports_outlined,
    Icons.notifications_outlined,
    Icons.account_balance_wallet_outlined,
    Icons.person_outline,
    Icons.settings_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    setState(() {
      _identityLoading = true;
      _identityError = null;
    });

    try {
      final identity = await _identityService.currentIdentity();

      if (!mounted) return;

      setState(() {
        _identity = identity;
        _identityLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _identity = null;
        _identityLoading = false;
        _identityError =
            'Could not read identity from secure storage. Check your '
            'keyring, then retry.';
      });
    }
  }

  Future<void> _openOnboarding() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const OnboardingPage(),
      ),
    );

    if (saved == true) {
      await _loadIdentity();
    }
  }

  Future<void> _removeIdentity() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove local key?'),
        content: const Text(
          'This removes the stored private key from this device. '
          'Make sure you have a backup before continuing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _identityService.deleteIdentity();
      await _loadIdentity();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local key removed.')),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove the local key.'),
        ),
      );
    }
  }

  void _openSupport() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SupportMolStrPage()),
    );
  }

  Widget _buildProfilePage() {
    if (_identityLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_identityError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 56),
              const SizedBox(height: 12),
              Text(_identityError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadIdentity,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final identity = _identity;

    if (identity == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 64),
            const SizedBox(height: 12),
            const Text('No Nostr identity connected'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openOnboarding,
              icon: const Icon(Icons.key_outlined),
              label: const Text('Get started'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openSupport,
              icon: const Icon(Icons.favorite_outline),
              label: const Text('Support MolStr'),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.key_outlined, size: 64),
          const SizedBox(height: 12),
          const Text('Local key connected'),
          const SizedBox(height: 8),
          SelectableText(
            _shortNpub(identity.npub),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _openSupport,
            icon: const Icon(Icons.favorite_outline),
            label: const Text('Support MolStr'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _removeIdentity,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove local key'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final pages = IndexedStack(
      index: _index,
      children: [
        const Center(
          child: Text(
            'Home Feed\n'
            'Notes, replies, reposts, likes, zaps, and tips coming next.',
            textAlign: TextAlign.center,
          ),
        ),
        const Center(child: Text('Nostr games showcase: coming next.')),
        const Center(child: Text('Notifications: coming next.')),
        const Center(
          child: Text('Wallet: NWC and Monero handoff coming next.'),
        ),
        _buildProfilePage(),
        SettingsPage(
          preset: widget.preset,
          font: widget.font,
          onPresetChanged: widget.onPresetChanged,
          onFontChanged: widget.onFontChanged,
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            SvgPicture.asset(
              'assets/logo/molstr_icon.svg',
              width: 32,
              height: 32,
              semanticsLabel: 'MolStr logo',
            ),
            const SizedBox(width: 12),
            Text('MolStr · ${_labels[_index]}'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Support MolStr',
            onPressed: _openSupport,
            icon: const Icon(Icons.favorite_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: (index) {
                      setState(() => _index = index);
                    },
                    destinations: [
                      for (var i = 0; i < _labels.length; i++)
                        NavigationRailDestination(
                          icon: Icon(_icons[i]),
                          label: Text(_labels[i]),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: pages),
                ],
              )
            : pages,
      ),
      bottomNavigationBar: wide
          ? null
          : BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: _index,
              selectedFontSize: 10,
              unselectedFontSize: 10,
              onTap: (index) => setState(() => _index = index),
              items: [
                for (var i = 0; i < _labels.length; i++)
                  BottomNavigationBarItem(
                    icon: Icon(_icons[i]),
                    label: i == 2 ? 'Alerts' : _labels[i],
                  ),
              ],
            ),
      floatingActionButton: _index == 0
          ? FloatingActionButton(
              tooltip: 'Create note',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                        Text('The note composer is not implemented yet.'),
                  ),
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}