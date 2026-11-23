import 'dart:convert';
import 'dart:math';

import 'package:bip340/bip340.dart' as bip340;
import 'package:crypto/crypto.dart';

import 'nip19.dart';

class NostrEvent {
  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;

  static final _hex64 = RegExp(r'^[0-9a-f]{64}$');
  static final _hex128 = RegExp(r'^[0-9a-f]{128}$');

  String get authorNpub => Nip19.npubFromHex(pubkey);

  bool get isReply => tags.any((tag) {
        if (tag.length < 2 || tag[0] != 'e') return false;
        final marker = tag.length >= 4 ? tag[3] : '';
        return marker == 'reply' || marker == 'root' || marker.isEmpty;
      });

  String get dTag {
    for (final tag in tags) {
      if (tag.length >= 2 && tag[0] == 'd') return tag[1];
    }
    return '';
  }

  String? get quotedEventId {
    for (final tag in tags) {
      if (tag.length >= 2 && tag[0] == 'q') return tag[1];
    }
    return null;
  }

  static String computeId({
    required String pubkey,
    required int createdAt,
    required int kind,
    required List<List<String>> tags,
    required String content,
  }) {
    final serialized = jsonEncode([
      0,
      pubkey,
      createdAt,
      kind,
      tags,
      content,
    ]);
    return sha256.convert(utf8.encode(serialized)).toString();
  }

  bool verify() {
    if (!_hex64.hasMatch(id) ||
        !_hex64.hasMatch(pubkey) ||
        !_hex128.hasMatch(sig)) {
      return false;
    }

    final expectedId = computeId(
      pubkey: pubkey,
      createdAt: createdAt,
      kind: kind,
      tags: tags,
      content: content,
    );

    if (expectedId != id) {
      return false;
    }

    try {
      return bip340.verify(pubkey, id, sig);
    } catch (_) {
      return false;
    }
  }

  static NostrEvent sign({
    required String privateKeyHex,
    required int kind,
    required String content,
    List<List<String>> tags = const [],
    int? createdAt,
  }) {
    final normalizedPriv = privateKeyHex.toLowerCase();
    if (!_hex64.hasMatch(normalizedPriv)) {
      throw const FormatException(
        'Private key must be 64 lowercase hex characters.',
      );
    }

    final pubkey = bip340.getPublicKey(normalizedPriv).toLowerCase();
    final timestamp =
        createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final id = computeId(
      pubkey: pubkey,
      createdAt: timestamp,
      kind: kind,
      tags: tags,
      content: content,
    );

    final random = Random.secure();
    final auxBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final auxHex = Nip19.bytesToHex(auxBytes);
    final sig = bip340.sign(normalizedPriv, id, auxHex).toLowerCase();

    return NostrEvent(
      id: id,
      pubkey: pubkey,
      createdAt: timestamp,
      kind: kind,
      tags: tags,
      content: content,
      sig: sig,
    );
  }

  static NostrEvent? fromJsonVerified(Map<String, dynamic> json) {
    final id = json['id'];
    final pubkey = json['pubkey'];
    final createdAt = json['created_at'];
    final kind = json['kind'];
    final rawTags = json['tags'];
    final content = json['content'];
    final sig = json['sig'];

    if (id is! String ||
        pubkey is! String ||
        createdAt is! int ||
        kind is! int ||
        rawTags is! List ||
        content is! String ||
        sig is! String) {
      return null;
    }

    final parsedTags = <List<String>>[];
    for (final tag in rawTags) {
      if (tag is! List) return null;
      final items = <String>[];
      for (final item in tag) {
        if (item is! String) return null;
        items.add(item);
      }
      parsedTags.add(items);
    }

    final event = NostrEvent(
      id: id,
      pubkey: pubkey,
      createdAt: createdAt,
      kind: kind,
      tags: parsedTags,
      content: content,
      sig: sig,
    );

    return event.verify() ? event : null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pubkey': pubkey,
        'created_at': createdAt,
        'kind': kind,
        'tags': tags,
        'content': content,
        'sig': sig,
      };
}

class ProfileMetadata {
  const ProfileMetadata({
    required this.pubkey,
    required this.createdAt,
    this.name,
    this.displayName,
    this.about,
    this.nip05,
    this.lud16,
    this.lud06,
    this.moneroAddress,
    this.picture,
    this.banner,
  });

  final String pubkey;
  final int createdAt;
  final String? name;
  final String? displayName;
  final String? about;
  final String? nip05;
  final String? lud16;
  final String? lud06;
  final String? moneroAddress;
  final String? picture;
  final String? banner;

  String get bestName {
    final dn = displayName?.trim();
    if (dn != null && dn.isNotEmpty) return dn;
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final npub = Nip19.npubFromHex(pubkey);
    return '${npub.substring(0, 12)}…${npub.substring(npub.length - 6)}';
  }

  static ProfileMetadata? fromKind0(NostrEvent event) {
    if (event.kind != 0) return null;
    try {
      final decoded = jsonDecode(event.content);
      if (decoded is! Map<String, dynamic>) return null;

      String? readField(String key) {
        final value = decoded[key];
        return value is String && value.trim().isNotEmpty ? value.trim() : null;
      }

      return ProfileMetadata(
          pubkey: event.pubkey,
          createdAt: event.createdAt,
          name: readField('name'),
          displayName: readField('display_name') ?? readField('displayName'),
          about: readField('about'),
          nip05: readField('nip05'),
          lud16: readField('lud16'),
          lud06: readField('lud06'),
          moneroAddress: readField('monero_address'),
          picture: readField('picture'),
          banner: readField('banner'));
    } catch (_) {
      return null;
    }
  }
}

class PollOption {
  const PollOption(this.index, this.label);
  final int index;
  final String label;
}

/// Read-only view of a NIP-88 poll (kind 1068).
/// Voting (kind 1018 responses) is a later slice — verify against
/// https://github.com/nostr-protocol/nips/blob/master/88.md before then.
class PollData {
  const PollData({
    required this.event,
    required this.options,
    required this.multipleChoice,
    this.endsAt,
  });

  final NostrEvent event;
  final List<PollOption> options;
  final bool multipleChoice;
  final int? endsAt;

  static PollData? fromEvent(NostrEvent event) {
    if (event.kind != 1068) return null;

    final options = <PollOption>[];
    var multiple = false;
    int? endsAt;

    for (final tag in event.tags) {
      if (tag.isEmpty) continue;
      switch (tag[0]) {
        case 'option':
          if (tag.length >= 3) {
            final index = int.tryParse(tag[1]);
            if (index != null) options.add(PollOption(index, tag[2]));
          }
        case 'polltype':
          if (tag.length >= 2 && tag[1] == 'multiplechoice') multiple = true;
        case 'endsAt':
          if (tag.length >= 2) endsAt = int.tryParse(tag[1]);
      }
    }

    if (options.length < 2) return null;
    options.sort((a, b) => a.index.compareTo(b.index));
    return PollData(
      event: event,
      options: options,
      multipleChoice: multiple,
      endsAt: endsAt,
    );
  }
}

/// Read-only view of a NIP-23 long-form article (kind 30023).
class ArticleData {
  const ArticleData({
    required this.event,
    required this.title,
    this.summary,
    required this.d,
  });

  final NostrEvent event;
  final String title;
  final String? summary;
  final String d;

  static ArticleData? fromEvent(NostrEvent event) {
    if (event.kind != 30023) return null;

    String? title;
    String? summary;
    var d = '';

    for (final tag in event.tags) {
      if (tag.length < 2) continue;
      switch (tag[0]) {
        case 'title':
          title = tag[1];
        case 'summary':
          summary = tag[1];
        case 'd':
          d = tag[1];
      }
    }

    if (title == null || title.isEmpty) return null;
    return ArticleData(event: event, title: title, summary: summary, d: d);
  }
}
