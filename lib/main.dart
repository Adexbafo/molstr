import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/donate/support_molstr.dart';
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
  int _index = 0;

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

  void _openSupport() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SupportMolStrPage()),
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
            'Home Feed\nNotes, replies, reposts, likes, zaps, and tips coming next.',
            textAlign: TextAlign.center,
          ),
        ),
        const Center(child: Text('Nostr games showcase: coming next.')),
        const Center(child: Text('Notifications: coming next.')),
        const Center(
          child: Text('Wallet: NWC and Monero handoff coming next.'),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_outline, size: 64),
              const SizedBox(height: 12),
              const Text('Profile setup: coming next.'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _openSupport,
                icon: const Icon(Icons.favorite_outline),
                label: const Text('Support MolStr'),
              ),
            ],
          ),
        ),
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
                    content: Text('The note composer is not implemented yet.'),
                  ),
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}