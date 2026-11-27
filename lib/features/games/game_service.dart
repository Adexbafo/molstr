import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/nostr/game_listing.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/relay_service.dart';

class GameEngagement {
  const GameEngagement({
    this.mentions = 0,
    this.ratingCount = 0,
    this.ratingSum = 0,
  });

  final int mentions;
  final int ratingCount;
  final int ratingSum;

  double get average => ratingCount == 0 ? 0 : ratingSum / ratingCount;
}

class GamesLoadResult {
  const GamesLoadResult({
    required this.all,
    required this.friendGames,
  });

  final List<GameListing> all;
  final List<GameListing> friendGames;
}

int parseStarRating(String content) {
  final stars = content.split('⭐').length - 1 + content.split('★').length - 1;
  if (stars > 0) return stars > 5 ? 5 : stars;

  final match = RegExp(r'(\d)\s*/\s*5').firstMatch(content);
  if (match != null) {
    final value = int.tryParse(match.group(1) ?? '');
    if (value != null && value > 0 && value <= 5) return value;
  }

  return 0;
}

class GameService {
  GameService({
    required this.relayService,
    required this.preferences,
  });

  final RelayService relayService;
  final SharedPreferences preferences;

  static const _manualKey = 'molstr.games.manual';
  static const _featuredKey = 'molstr.games.featured';

  List<GameListing> loadManualGames() {
    final raw = preferences.getStringList(_manualKey) ?? const [];
    final games = <GameListing>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          final game = GameListing.fromJson(decoded);
          if (game != null) games.add(game);
        }
      } catch (_) {}
    }
    return games;
  }

  Future<void> addManualGame(GameListing game) async {
    final games = loadManualGames()
        .where((item) => item.address != game.address)
        .toList()
      ..add(game);

    await preferences.setStringList(
      _manualKey,
      games.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  String? getFeaturedGameAddress() => preferences.getString(_featuredKey);

  Future<void> setFeaturedGame(String address) async {
    await preferences.setString(_featuredKey, address);
  }

  Future<GamesLoadResult> loadGames({required String? viewerPubkey}) async {
    final byAddress = <String, GameListing>{};
    final friendAddresses = <String>{};

    final filters = [
      {
        'kinds': [31990],
        '#t': ['nostr-game'],
        'limit': 100
      },
      {
        'kinds': [31990],
        '#t': ['game'],
        'limit': 100
      },
    ];

    for (final filter in filters) {
      final query =
          await relayService.queryEvents(filter, relayService.loadRelays());
      for (final event in query.events) {
        final game = GameListing.fromEvent(event);
        if (game == null) continue;
        byAddress[game.address] = game;
      }
    }

    if (viewerPubkey != null) {
      final follows = <String>{
        ...?preferences.getStringList('molstr.follows.v2.$viewerPubkey'),
        ...?preferences.getStringList('molstr.follows.$viewerPubkey'),
      }.toList();

      if (follows.isNotEmpty) {
        final query = await relayService.queryEvents(
          {
            'kinds': [31990],
            'authors': follows.take(80).toList(),
            'limit': 100,
          },
          relayService.loadRelays(),
        );
        for (final event in query.events) {
          final game = GameListing.fromEvent(event);
          if (game == null) continue;
          byAddress[game.address] = game;
          friendAddresses.add(game.address);
        }
      }
    }

    for (final game in loadManualGames()) {
      byAddress.putIfAbsent(game.address, () => game);
    }

    final all = byAddress.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final friendGames =
        all.where((game) => friendAddresses.contains(game.address)).toList();

    return GamesLoadResult(all: all, friendGames: friendGames);
  }

  Future<Map<String, GameEngagement>> loadEngagement(
    List<GameListing> games,
  ) async {
    final tags = games.map((game) => game.d).toSet().toList();
    if (tags.isEmpty) return const {};

    final query = await relayService.queryEvents(
      {
        'kinds': [1],
        '#t': tags,
        'limit': 200,
      },
      relayService.loadRelays(),
    );

    final result = <String, GameEngagement>{
      for (final game in games) game.d: const GameEngagement(),
    };

    for (final event in query.events) {
      final noteTags = event.tags
          .where((tag) => tag.length >= 2 && tag[0] == 't')
          .map((tag) => tag[1].toLowerCase())
          .toSet();

      final stars = parseStarRating(event.content);

      for (final game in games) {
        if (!noteTags.contains(game.d.toLowerCase())) continue;

        final current = result[game.d]!;
        result[game.d] = GameEngagement(
          mentions: current.mentions + 1,
          ratingCount: current.ratingCount + (stars > 0 ? 1 : 0),
          ratingSum: current.ratingSum + stars,
        );
      }
    }

    return result;
  }

  Future<List<NostrEvent>> loadCommunity(String gameTag) async {
    final query = await relayService.queryEvents(
      {
        'kinds': [1],
        '#t': [gameTag],
        'limit': 100,
      },
      relayService.loadRelays(),
    );

    final events = query.events.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return events;
  }
}
