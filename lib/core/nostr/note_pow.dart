import 'package:flutter/foundation.dart';

import 'nostr_event.dart';

class NotePowException implements Exception {
  const NotePowException(this.message);

  final String message;
}

typedef MinedNote = ({
  String id,
  int createdAt,
  List<List<String>> tags,
});

typedef _Work = ({
  String pubkey,
  int createdAt,
  String content,
  List<List<String>> tags,
  int bits,
});

final _hexId = RegExp(r'^[0-9a-f]{64}$');

int leadingZeroBits(String id) {
  if (id.length != 64 || !_hexId.hasMatch(id)) {
    throw const FormatException('Expected a lowercase hexadecimal event ID.');
  }

  var bits = 0;
  for (var i = 0; i < id.length; i++) {
    final nibble = int.parse(id[i], radix: 16);
    if (nibble == 0) {
      bits += 4;
    } else {
      return bits +
          (nibble < 2
              ? 3
              : nibble < 4
                  ? 2
                  : nibble < 8
                      ? 1
                      : 0);
    }
  }
  return bits;
}

/// Returns the committed difficulty from a NIP-13 nonce tag, or null.
int? powDifficultyFromTags(List<List<String>> tags) {
  for (final tag in tags) {
    if (tag.length >= 3 && tag[0] == 'nonce') {
      final bits = int.tryParse(tag[2]);
      if (bits != null && bits > 0) return bits;
    }
  }
  return null;
}

Future<MinedNote> mineTextNote({
  required String pubkey,
  required int createdAt,
  required String content,
  required List<List<String>> tags,
  required int bits,
}) {
  if (bits < 1 || bits > 12) {
    throw const NotePowException('Choose a difficulty between 1 and 12 bits.');
  }

  return compute(
    _mine,
    (
      pubkey: pubkey,
      createdAt: createdAt,
      content: content,
      tags: tags,
      bits: bits,
    ),
  );
}

MinedNote _mine(_Work work) {
  final nonceTag = <String>['nonce', '0', '${work.bits}'];
  final tags = <List<String>>[
    for (final tag in work.tags)
      if (tag.isEmpty || tag.first != 'nonce') List<String>.of(tag),
    nonceTag,
  ];

  final stopwatch = Stopwatch()..start();
  for (var nonce = 0;
      nonce < 65536 && stopwatch.elapsedMilliseconds < 4000;
      nonce++) {
    nonceTag[1] = '$nonce';

    final id = NostrEvent.computeId(
      pubkey: work.pubkey,
      createdAt: work.createdAt,
      kind: 1,
      tags: tags,
      content: work.content,
    );

    if (leadingZeroBits(id) >= work.bits) {
      return (id: id, createdAt: work.createdAt, tags: tags);
    }
  }

  throw const NotePowException(
    'Proof of work wasn’t found in time. Try 8 bits or turn it off.',
  );
}
