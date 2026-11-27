import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'nostr_event.dart';

class GameListing {
  const GameListing({
    required this.d,
    required this.name,
    required this.about,
    required this.developerPubkey,
    required this.links,
    this.picture,
    this.lud16,
    this.moneroAddress,
    this.sourceRelay = '',
    this.createdAt = 0,
    this.manual = false,
  });

  final String d;
  final String name;
  final String about;
  final String developerPubkey;
  final Map<String, String> links;
  final String? picture;
  final String? lud16;
  final String? moneroAddress;
  final String sourceRelay;
  final int createdAt;
  final bool manual;

  String get address => '31990:$developerPubkey:$d';

  String? linkFor(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.android => links['android'] ?? links['web'],
      TargetPlatform.iOS => links['ios'] ?? links['web'],
      TargetPlatform.macOS => links['web'],
      TargetPlatform.windows => links['web'],
      TargetPlatform.linux => links['web'],
      _ => links['web'],
    };
  }

  static GameListing? fromEvent(NostrEvent event) {
    if (event.kind != 31990) return null;

    final d = _tag(event.tags, 'd');
    if (d == null || d.isEmpty) return null;

    Map<String, dynamic>? meta;
    try {
      final decoded = jsonDecode(event.content);
      if (decoded is Map<String, dynamic>) meta = decoded;
    } catch (_) {}

    String? readMeta(String key) {
      final value = meta?[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    final name = readMeta('name') ?? _tag(event.tags, 'name') ?? d;
    final about = readMeta('about') ?? _tag(event.tags, 'about') ?? '';
    final picture = readMeta('picture') ?? _tag(event.tags, 'picture');

    final devTags = event.tags
        .where((tag) => tag.length >= 2 && tag[0] == 'p')
        .map((tag) => tag[1])
        .toList();

    final developer = devTags.isEmpty ? event.pubkey : devTags.first;

    final linkKeys = {
      'web',
      'website',
      'url',
      'android',
      'ios',
      'windows',
      'macos',
      'linux',
    };

    final parsedLinks = <String, String>{};
    for (final tag in event.tags) {
      if (tag.length < 2 || !linkKeys.contains(tag[0])) continue;
      final key = tag[0] == 'website' || tag[0] == 'url' ? 'web' : tag[0];
      final value = tag[1].trim();
      if (value.isNotEmpty) parsedLinks[key] = value;
    }

    return GameListing(
      d: d,
      name: name,
      about: about,
      developerPubkey: developer,
      links: parsedLinks,
      picture: picture,
      lud16: readMeta('lud16') ?? _tag(event.tags, 'lud16'),
      moneroAddress:
          readMeta('monero_address') ?? _tag(event.tags, 'monero_address'),
      sourceRelay: '',
      createdAt: event.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'd': d,
        'name': name,
        'about': about,
        'developerPubkey': developerPubkey,
        'links': links,
        'picture': picture,
        'lud16': lud16,
        'moneroAddress': moneroAddress,
        'sourceRelay': sourceRelay,
        'createdAt': createdAt,
        'manual': manual,
      };

  static GameListing? fromJson(Map<String, dynamic> json) {
    final d = json['d'];
    final name = json['name'];
    final developer = json['developerPubkey'];
    if (d is! String || name is! String || developer is! String) return null;

    final rawLinks = json['links'];
    final links = <String, String>{};
    if (rawLinks is Map) {
      rawLinks.forEach((key, value) {
        if (key is String && value is String) links[key] = value;
      });
    }

    return GameListing(
      d: d,
      name: name,
      about: json['about'] is String ? json['about'] as String : '',
      developerPubkey: developer,
      links: links,
      picture: json['picture'] is String ? json['picture'] as String : null,
      lud16: json['lud16'] is String ? json['lud16'] as String : null,
      moneroAddress: json['moneroAddress'] is String
          ? json['moneroAddress'] as String
          : null,
      sourceRelay:
          json['sourceRelay'] is String ? json['sourceRelay'] as String : '',
      createdAt: json['createdAt'] is int ? json['createdAt'] as int : 0,
      manual: json['manual'] == true,
    );
  }

  static String? _tag(List<List<String>> tags, String key) {
    for (final tag in tags) {
      if (tag.length >= 2 && tag[0] == key) return tag[1];
    }
    return null;
  }
}
