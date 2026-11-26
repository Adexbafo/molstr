import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/nostr/identity_service.dart';
import 'core/nostr/relay_service.dart';
import 'features/donate/support_molstr.dart';
import 'features/home/home_feed_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/profile/profile_page.dart';
import 'features/settings/settings_page.dart';
import 'ui/theme/app_theme.dart';
import 'features/composer/note_composer_page.dart';
import 'core/nostr/interactions.dart';
import 'features/tools/tools_page.dart';
import 'ui/widgets/account_switcher_sheet.dart';
import 'features/notifications/notifications_page.dart';
import 'features/messages/messages_page.dart';
import 'features/settings/dm_relays_page.dart';
import 'features/wallet/wallet_page.dart';

const _themeKey = 'appearance.theme';
const _fontKey = 'appearance.font';
const _imagesKey = 'privacy.loadImages';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(ProviderScope(child: MolStrApp(preferences: preferences)));
}

T _readEnum<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
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
  late final RelayService _relayService;
  late MolStrPreset _preset;
  late MolStrFont _font;
  late bool _loadImages;
  late List<String> _relays;

  @override
  void initState() {
    super.initState();
    _relayService = RelayService(preferences: widget.preferences);
    _preset = _readEnum(MolStrPreset.values,
        widget.preferences.getString(_themeKey), MolStrPreset.nightInk);
    _font = _readEnum(MolStrFont.values, widget.preferences.getString(_fontKey),
        MolStrFont.system);
    _loadImages = widget.preferences.getBool(_imagesKey) ?? false;
    _relays = _relayService.loadRelays();
  }

  Future<void> _savePermission(String key, String value) async {
    final saved = await widget.preferences.setString(key, value);
    if (!saved) throw StateError('Could not save $key');
  }

  Future<void> _changePreset(MolStrPreset p) async {
    setState(() => _preset = p);
    await _savePermission(_themeKey, p.name);
  }

  Future<void> _changeFont(MolStrFont f) async {
    setState(() => _font = f);
    await _savePermission(_fontKey, f.name);
  }

  Future<void> _changeLoadImages(bool value) async {
    setState(() => _loadImages = value);
    await widget.preferences.setBool(_imagesKey, value);
  }

  Future<void> _addRelay(String rawUrl) async {
    final normalized = RelayService.normalizeRelayUrl(rawUrl);
    if (_relays.contains(normalized)) {
      throw const FormatException('Relay is already in your list.');
    }
    final next = [..._relays, normalized];
    setState(() => _relays = next);
    await _relayService.saveRelays(next);
  }

  Future<void> _removeRelay(String url) async {
    final next = _relays.where((r) => r != url).toList();
    setState(() => _relays = next);
    await _relayService.saveRelays(next);
  }

  Future<void> _resetRelays() async {
    final next = List<String>.from(RelayService.defaultRelays);
    setState(() => _relays = next);
    await _relayService.saveRelays(next);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MolStr',
        debugShowCheckedModeBanner: false,
        theme: MolStrTheme.forPreset(_preset, _font),
        home: MolStrShell(
          preset: _preset,
          font: _font,
          loadImages: _loadImages,
          onPresetChanged: _changePreset,
          onFontChanged: _changeFont,
          onLoadImagesChanged: _changeLoadImages,
          relays: _relays,
          relayService: _relayService,
          onAddRelay: _addRelay,
          onRemoveRelay: _removeRelay,
          onResetRelays: _resetRelays,
          preferences: widget.preferences,
        ),
      );
}

class MolStrShell extends StatefulWidget {
  const MolStrShell({
    super.key,
    required this.preset,
    required this.font,
    required this.loadImages,
    required this.onPresetChanged,
    required this.onFontChanged,
    required this.onLoadImagesChanged,
    required this.relays,
    required this.relayService,
    required this.onAddRelay,
    required this.onRemoveRelay,
    required this.onResetRelays,
    required this.preferences,
  });

  final MolStrPreset preset;
  final MolStrFont font;
  final bool loadImages;
  final Future<void> Function(MolStrPreset) onPresetChanged;
  final Future<void> Function(MolStrFont) onFontChanged;
  final Future<void> Function(bool) onLoadImagesChanged;
  final List<String> relays;
  final RelayService relayService;
  final Future<void> Function(String url) onAddRelay;
  final Future<void> Function(String url) onRemoveRelay;
  final Future<void> Function() onResetRelays;
  final SharedPreferences preferences;

  @override
  State<MolStrShell> createState() => _MolStrShellState();
}

class _MolStrShellState extends State<MolStrShell> {
  final _identityService = IdentityService();

  int _index = 0;
  int _feedRefreshToken = 0;
  Identity? _identity;
  bool _identityLoading = true;
  String? _identityError;

  static const _labels = [
    'Home',
    'Games',
    'Notifications',
    'Messages',
    'Wallet',
    'Profile',
    'Settings',
  ];
  static const _icons = [
    Icons.home_outlined,
    Icons.sports_esports_outlined,
    Icons.notifications_outlined,
    Icons.mail_outline,
    Icons.account_balance_wallet_outlined,
    Icons.person_outline,
    Icons.settings_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  void _openTools() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ToolsPage(
          identityService: _identityService,
          relayService: widget.relayService,
          relays: widget.relays,
          preferences: widget.preferences,
        ),
      ),
    );
  }

  void _openDmRelays() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DmRelaysPage(
          identityService: _identityService,
          relayService: widget.relayService,
          selectedRelays: widget.relays,
        ),
      ),
    );
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
        _identityError = 'Could not read identity from secure storage.';
      });
    }
  }

  Future<void> _openOnboarding() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const OnboardingPage(),
      ),
    );

    if (!mounted) return;
    if (saved == true) {
      await _loadIdentity();
    }
  }

  Future<void> _openComposer() async {
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => NoteComposerPage(
          identityService: _identityService,
          relayService: widget.relayService,
          relays: widget.relays,
        ),
      ),
    );
    if (published == true && mounted) {
      setState(() => _feedRefreshToken++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Published. Refreshing feed…')),
      );
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
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove')),
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
        const SnackBar(content: Text('Could not remove the local key.')),
      );
    }
  }

  void _openSupport() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SupportMolStrPage()),
    );
  }

  Widget _profilePage() {
    if (_identityLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_identityError != null) {
      return Center(child: Text(_identityError!));
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
              onPressed: () => showAccountSwitcherSheet(
                context: context,
                identityService: _identityService,
                activeIdentity: null,
                onRefresh: _loadIdentity,
              ),
              icon: const Icon(Icons.switch_account),
              label: const Text('Switch / Manage Accounts'),
            ),
          ],
        ),
      );
    }

    return ProfilePage(
      key: ValueKey(identity.pubkey),
      identity: identity,
      identityService: _identityService,
      relayService: widget.relayService,
      relays: widget.relays,
      loadImages: widget.loadImages,
      onOpenSupport: _openSupport,
      onRemoveIdentity: _removeIdentity,
      onAccountsChanged: _loadIdentity,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final pages = IndexedStack(
      index: _index,
      children: [
        HomeFeedPage(
          relays: widget.relays,
          relayService: widget.relayService,
          onOpenRelaySettings: () => setState(() => _index = 5),
          loadImages: widget.loadImages,
          refreshToken: _feedRefreshToken,
          key: ValueKey(('home', _identity?.pubkey, widget.relays.join('\n'))),
          viewerPubkey: _identity?.pubkey,
        ),
        const Center(child: Text('Nostr games showcase: coming next.')),
        NotificationsPage(
          key: ValueKey(_identity?.pubkey ?? 'signed-out'),
          relayService: widget.relayService,
          relays: widget.relays,
          pubkey: _identity?.pubkey,
          loadImages: widget.loadImages,
        ),
        MessagesPage(
          key: ValueKey(_identity?.pubkey ?? 'signed-out'),
          identityService: _identityService,
          relayService: widget.relayService,
          relays: widget.relays,
          pubkey: _identity?.pubkey,
          loadImages: widget.loadImages,
        ),
        WalletPage(
          key: ValueKey(_identity?.pubkey ?? 'signed-out'),
          relayService: widget.relayService,
        ),
        _profilePage(),
        SettingsPage(
          preset: widget.preset,
          font: widget.font,
          onPresetChanged: widget.onPresetChanged,
          onFontChanged: widget.onFontChanged,
          loadImages: widget.loadImages,
          onLoadImagesChanged: widget.onLoadImagesChanged,
          relays: widget.relays,
          onAddRelay: widget.onAddRelay,
          onRemoveRelay: widget.onRemoveRelay,
          onResetRelays: widget.onResetRelays,
          onOpenTools: _openTools,
          onOpenDmRelays: _openDmRelays,
          identityService: _identityService,
          relayService: widget.relayService,
          preferences: widget.preferences,
          selectedRelays: widget.relays,
        ),
      ],
    );

    final interactions = Interactions(
      identityService: _identityService,
      relayService: widget.relayService,
      relays: widget.relays,
      preferences: widget.preferences,
      canSign: _identity != null,
    );

    return InteractionsScope(
      interactions: interactions,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              SvgPicture.asset('assets/logo/molstr_icon.svg',
                  width: 32, height: 32, semanticsLabel: 'MolStr logo'),
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
                      onDestinationSelected: (i) => setState(() => _index = i),
                      destinations: [
                        for (var i = 0; i < _labels.length; i++)
                          NavigationRailDestination(
                              icon: Icon(_icons[i]), label: Text(_labels[i])),
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
                onTap: (i) => setState(() => _index = i),
                items: [
                  for (var i = 0; i < _labels.length; i++)
                    BottomNavigationBarItem(
                        icon: Icon(_icons[i]),
                        label: i == 2 ? 'Alerts' : _labels[i]),
                ],
              ),
        floatingActionButton: _index == 0
            ? FloatingActionButton(
                tooltip: 'Create note',
                onPressed: _openComposer,
                child: const Icon(Icons.add),
              )
            : null,
      ),
    );
  }
}
