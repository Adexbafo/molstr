import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/nostr/game_listing.dart';
import '../../core/nostr/identity_service.dart';
import '../../core/nostr/nip19.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/relay_service.dart';
import '../../core/payments/monero.dart';
import '../../ui/payments/monero_sheet.dart';
import '../../ui/payments/zap_sheet.dart';
import '../../ui/render/note_card.dart' show formatTimestamp;
import 'game_service.dart';

class GamesPage extends StatefulWidget {
  const GamesPage({
    super.key,
    required this.identityService,
    required this.relayService,
    required this.relays,
    required this.preferences,
    required this.loadImages,
  });

  final IdentityService identityService;
  final RelayService relayService;
  final List<String> relays;
  final SharedPreferences preferences;
  final bool loadImages;

  @override
  State<GamesPage> createState() => _GamesPageState();
}

class _GamesPageState extends State<GamesPage> {
  late final GameService _service;

  List<GameListing> _games = const [];
  List<GameListing> _friendGames = const [];
  Map<String, GameEngagement> _engagement = const {};
  String? _featuredAddress;

  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = GameService(
      relayService: widget.relayService,
      preferences: widget.preferences,
    );
    _featuredAddress = _service.getFeaturedGameAddress();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final me = await widget.identityService.currentIdentity();
      final result = await _service.loadGames(viewerPubkey: me?.pubkey);
      if (!mounted) return;

      setState(() {
        _games = result.all;
        _friendGames = result.friendGames;
        _featuredAddress = _service.getFeaturedGameAddress();
        _loading = false;
        _loadedOnce = true;
      });

      unawaited(_loadEngagement());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadedOnce = true;
        _error = 'Could not load games from your relays.';
      });
    }
  }

  Future<void> _loadEngagement() async {
    final counts = await _service.loadEngagement(_games);
    if (!mounted) return;
    setState(() => _engagement = counts);
  }

  Future<void> _addGame() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final npubController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add game manually'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Game name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'https:// game URL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: npubController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Developer npub (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) {
      nameController.dispose();
      urlController.dispose();
      npubController.dispose();
      return;
    }

    final name = nameController.text.trim();
    final url = urlController.text.trim();
    final npub = npubController.text.trim();
    nameController.dispose();
    urlController.dispose();
    npubController.dispose();

    if (name.isEmpty) {
      _message('Enter a game name.');
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      _message('Use a full https:// game URL.');
      return;
    }

    var developer = '0' * 64;
    if (npub.isNotEmpty) {
      try {
        developer = Nip19.hexFromNpub(npub);
      } catch (_) {
        _message('Invalid developer npub.');
        return;
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final d =
        'manual-$now-${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';

    await _service.addManualGame(
      GameListing(
        d: d,
        name: name,
        about: 'Manually added game',
        developerPubkey: developer,
        links: {'web': url},
        createdAt: now,
        manual: true,
      ),
    );

    _message('Game added locally.');
    await _load();
  }

  Future<void> _openLink(GameListing game) async {
    final link = game.linkFor(defaultTargetPlatform) ?? game.links['web'];
    if (link == null) {
      _message('This game has no playable link.');
      return;
    }

    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      _message('Game link must use https://.');
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _zap(GameListing game) async {
    final lud16 = game.lud16;
    if (lud16 == null || lud16.trim().isEmpty) {
      _message('Developer has no Lightning address.');
      return;
    }

    await showZapSheet(
      context: context,
      recipientName: game.name,
      recipientLud16: lud16.trim(),
      recipientPubkeyHex: game.developerPubkey,
      noteEvent: null,
      relays: widget.relays,
      identityService: widget.identityService,
      relayService: widget.relayService,
    );
  }

  Future<void> _tipMonero(GameListing game) async {
    final address = game.moneroAddress;
    if (address == null || address.trim().isEmpty) {
      _message('Developer has no Monero address.');
      return;
    }
    if (!isValidMoneroAddress(address)) {
      _message('Developer Monero address looks invalid.');
      return;
    }

    await showMoneroSheet(
      context: context,
      recipientName: game.name,
      moneroAddress: address.trim(),
      notePreview: game.about,
    );
  }

  Future<void> _openCommunity(GameListing game) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => GameCommunityPage(
          title: game.name,
          gameTag: game.d,
          service: _service,
        ),
      ),
    );
  }

  Future<void> _setFeatured(GameListing game) async {
    await _service.setFeaturedGame(game.address);
    if (!mounted) return;
    setState(() => _featuredAddress = game.address);
    _message('Game of the Week updated locally.');
  }

  Widget _featuredCard() {
    if (_featuredAddress == null) return const SizedBox.shrink();
    final game = _games.where((g) => g.address == _featuredAddress).toList();
    if (game.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Game of the Week',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _GameCard(
              game: game.first,
              engagement: _engagement[game.first.d],
              loadImages: widget.loadImages,
              onTry: () => _openLink(game.first),
              onZap: () => _zap(game.first),
              onTip: () => _tipMonero(game.first),
              onCommunity: () => _openCommunity(game.first),
              onFeature: null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (!_loadedOnce && !_loading) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Icon(Icons.sports_esports,
                  size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Nostr Games Hub',
                style: textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Discover games announced on Nostr through NIP-89 handlers. '
                'MolStr loads listings only when you ask, verifies events, '
                'and opens games externally.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.sync),
                label: const Text('Load games'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _addGame,
                icon: const Icon(Icons.add),
                label: const Text('Add game manually'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${_games.length} games observed'
                '${_friendGames.isEmpty ? '' : ' · ${_friendGames.length} from follows'}',
                style: textTheme.bodySmall,
              ),
              FilledButton.icon(
                onPressed: _loading ? null : _load,
                icon: _loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(_loading ? 'Loading…' : 'Refresh'),
              ),
              OutlinedButton.icon(
                onPressed: _addGame,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add game'),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const Divider(height: 1),
        Expanded(
          child: _loading && _games.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _featuredCard(),
                    if (_friendGames.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Friends playing', style: textTheme.titleLarge),
                      const SizedBox(height: 8),
                      for (final game in _friendGames)
                        _GameCard(
                          game: game,
                          engagement: _engagement[game.d],
                          loadImages: widget.loadImages,
                          onTry: () => _openLink(game),
                          onZap: () => _zap(game),
                          onTip: () => _tipMonero(game),
                          onCommunity: () => _openCommunity(game),
                          onFeature: () => _setFeatured(game),
                        ),
                    ],
                    const SizedBox(height: 16),
                    Text('All games', style: textTheme.titleLarge),
                    const SizedBox(height: 8),
                    if (_games.isEmpty)
                      const Text(
                        'No NIP-89 game handlers were found on your relays yet. '
                        'You can add one manually.',
                      )
                    else
                      for (final game in _games)
                        _GameCard(
                          game: game,
                          engagement: _engagement[game.d],
                          loadImages: widget.loadImages,
                          onTry: () => _openLink(game),
                          onZap: () => _zap(game),
                          onTip: () => _tipMonero(game),
                          onCommunity: () => _openCommunity(game),
                          onFeature: () => _setFeatured(game),
                        ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.game,
    required this.engagement,
    required this.loadImages,
    required this.onTry,
    required this.onZap,
    required this.onTip,
    required this.onCommunity,
    required this.onFeature,
  });

  final GameListing game;
  final GameEngagement? engagement;
  final bool loadImages;
  final VoidCallback onTry;
  final VoidCallback onZap;
  final VoidCallback onTip;
  final VoidCallback onCommunity;
  final VoidCallback? onFeature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rating = engagement == null
        ? ''
        : engagement!.ratingCount > 0
            ? '★ ${engagement!.average.toStringAsFixed(1)} '
                '(${engagement!.ratingCount}) · ${engagement!.mentions} mentions'
            : '${engagement!.mentions} mentions';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: game.picture != null &&
                          loadImages &&
                          game.picture!.startsWith('https://')
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            game.picture!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.sports_esports),
                          ),
                        )
                      : const Icon(Icons.sports_esports),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (game.about.isNotEmpty)
                        Text(game.about, style: theme.textTheme.bodySmall),
                      if (rating.isNotEmpty)
                        Text(rating, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onTry,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Try'),
                ),
                OutlinedButton.icon(
                  onPressed: onCommunity,
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('Community'),
                ),
                OutlinedButton.icon(
                  onPressed: onZap,
                  icon: const Icon(Icons.bolt_outlined),
                  label: const Text('Zap dev'),
                ),
                OutlinedButton.icon(
                  onPressed: onTip,
                  icon: const Icon(Icons.shield_outlined),
                  label: const Text('Tip XMR'),
                ),
                if (onFeature != null)
                  OutlinedButton.icon(
                    onPressed: onFeature,
                    icon: const Icon(Icons.star_border),
                    label: const Text('Feature'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class GameCommunityPage extends StatefulWidget {
  const GameCommunityPage({
    super.key,
    required this.title,
    required this.gameTag,
    required this.service,
  });

  final String title;
  final String gameTag;
  final GameService service;

  @override
  State<GameCommunityPage> createState() => _GameCommunityPageState();
}

class _GameCommunityPageState extends State<GameCommunityPage> {
  List<NostrEvent> _notes = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notes = await widget.service.loadCommunity(widget.gameTag);
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text('Community: ${widget.title}', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No community notes found for this game on your relays.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _notes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final note = _notes[index];
                    final text = note.content.length > 240
                        ? '${note.content.substring(0, 240)}…'
                        : note.content;
                    return ListTile(
                      title: Text(text),
                      subtitle: Text(formatTimestamp(note.createdAt)),
                    );
                  },
                ),
    );
  }
}
