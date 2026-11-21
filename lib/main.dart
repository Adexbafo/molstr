import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/donate/support_molstr.dart';
import 'features/settings/settings_page.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      child: MolStrApp(preferences: preferences),
    ),
  );
}

class MolStrApp extends StatefulWidget {
  const MolStrApp({super.key, required this.preferences});

  final SharedPreferences preferences;

  @override
  State<MolStrApp> createState() => _MolStrAppState();
}

class _MolStrAppState extends State<MolStrApp> {
  late MolStrPreset _preset;

  @override
  void initState() {
    super.initState();

    final saved = widget.preferences.getString('appearance.theme');
    _preset = MolStrPreset.values.firstWhere(
      (item) => item.name == saved,
      orElse: () => MolStrPreset.nightInk,
    );
  }

  Future<void> _changePreset(MolStrPreset preset) async {
    setState(() => _preset = preset);

    final saved = await widget.preferences.setString(
      'appearance.theme',
      preset.name,
    );

    if (!saved) {
      throw StateError('Could not save theme preference');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MolStr',
      debugShowCheckedModeBanner: false,
      theme: MolStrTheme.forPreset(_preset),
      home: MolStrShell(
        preset: _preset,
        onPresetChanged: _changePreset,
      ),
    );
  }
}

class MolStrShell extends StatefulWidget {
  const MolStrShell({
    super.key,
    required this.preset,
    required this.onPresetChanged,
  });

  final MolStrPreset preset;
  final Future<void> Function(MolStrPreset) onPresetChanged;

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
      MaterialPageRoute<void>(
        builder: (_) => const SupportMolStrPage(),
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
            'Home Feed\nNotes, replies, reposts, likes, zaps, and tips coming next.',
            textAlign: TextAlign.center,
          ),
        ),
        const Center(
          child: Text('Nostr games showcase — coming next.'),
        ),
        const Center(child: Text('Notifications — coming next.')),
        const Center(
          child: Text('Wallet — NWC and Monero handoff coming next.'),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_outline, size: 64),
              const SizedBox(height: 12),
              const Text('Profile setup — coming next.'),
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
          onPresetChanged: widget.onPresetChanged,
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