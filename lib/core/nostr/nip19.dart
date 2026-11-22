class Bech32Value {
  const Bech32Value({
    required this.hrp,
    required this.words,
  });

  final String hrp;
  final List<int> words;
}

class Nip19 {
  static const _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

  static const _generators = [
    0x3b6a57b2,
    0x26508e6d,
    0x1ea119fa,
    0x3d4233dd,
    0x2a1462b3,
  ];

  static String nsecFromHex(String privateKeyHex) =>
      encodeKey('nsec', privateKeyHex);

  static String npubFromHex(String publicKeyHex) =>
      encodeKey('npub', publicKeyHex);

  static String hexFromNsec(String nsec) =>
      hexFromKey(nsec, expectedHrp: 'nsec');

  static String hexFromNpub(String npub) =>
      hexFromKey(npub, expectedHrp: 'npub');

  static String encodeKey(String hrp, String hex) {
    final bytes = hexToBytes(hex);
    if (bytes.length != 32) {
      throw const FormatException('Nostr keys must be 32 bytes.');
    }

    final words = convertBits(data: bytes, from: 8, to: 5, pad: true);
    return encode(hrp, words);
  }

  static String hexFromKey(
    String value, {
    required String expectedHrp,
  }) {
    final decoded = decode(value);

    if (decoded.hrp != expectedHrp) {
      throw FormatException('Expected $expectedHrp key.');
    }

    final bytes = convertBits(
      data: decoded.words,
      from: 5,
      to: 8,
      pad: false,
    );

    if (bytes.length != 32) {
      throw const FormatException('Nostr keys must be 32 bytes.');
    }

    return bytesToHex(bytes);
  }

  static String encode(String hrp, List<int> words) {
    final lowerHrp = hrp.toLowerCase();

    for (final word in words) {
      if (word < 0 || word >= 32) {
        throw const FormatException('Invalid bech32 data.');
      }
    }

    final expandedHrp = _hrpExpand(lowerHrp);
    final checksumInput = [
      ...expandedHrp,
      ...words,
      0,
      0,
      0,
      0,
      0,
      0,
    ];

    final polymod = _polymod(checksumInput) ^ 1;

    final checksum = List<int>.generate(
      6,
      (i) => (polymod >> (5 * (5 - i))) & 31,
    );

    final combined = [...words, ...checksum];

    return lowerHrp + '1' + combined.map((value) => _charset[value]).join();
  }

  static Bech32Value decode(String input) {
    if (input.length < 8) {
      throw const FormatException('Key is too short.');
    }

    final hasLower = input.contains(RegExp('[a-z]'));
    final hasUpper = input.contains(RegExp('[A-Z]'));

    if (hasLower && hasUpper) {
      throw const FormatException('Mixed-case bech32 is not allowed.');
    }

    final value = input.toLowerCase();
    final separator = value.lastIndexOf('1');

    if (separator < 1 || separator + 7 > value.length) {
      throw const FormatException('Invalid bech32 separator.');
    }

    final hrp = value.substring(0, separator);
    final dataPart = value.substring(separator + 1);

    final values = <int>[];

    for (final codeUnit in dataPart.codeUnits) {
      final index = _charset.codeUnits.indexOf(codeUnit);
      if (index == -1) {
        throw const FormatException('Invalid bech32 character.');
      }
      values.add(index);
    }

    final check = _polymod([
      ..._hrpExpand(hrp),
      ...values,
    ]);

    if (check != 1) {
      throw const FormatException('Invalid bech32 checksum.');
    }

    return Bech32Value(
      hrp: hrp,
      words: values.sublist(0, values.length - 6),
    );
  }

  static List<int> convertBits({
    required List<int> data,
    required int from,
    required int to,
    required bool pad,
  }) {
    if (from < 1 || from > 8 || to < 1 || to > 8) {
      throw ArgumentError('Invalid bit conversion.');
    }

    var accumulator = 0;
    var bits = 0;
    final maxValue = (1 << to) - 1;
    final result = <int>[];

    for (final value in data) {
      if (value < 0 || value >= (1 << from)) {
        throw const FormatException('Invalid data for bit conversion.');
      }

      accumulator = (accumulator << from) | value;
      bits += from;

      while (bits >= to) {
        bits -= to;
        result.add((accumulator >> bits) & maxValue);
      }
    }

    if (pad) {
      if (bits > 0) {
        result.add((accumulator << (to - bits)) & maxValue);
      }
      return result;
    }

    if (bits >= from) {
      throw const FormatException('Invalid padding.');
    }

    if (((accumulator << (to - bits)) & maxValue) != 0) {
      throw const FormatException('Invalid padding.');
    }

    return result;
  }

  static String bytesToHex(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<int> hexToBytes(String hex) {
    final normalized = hex.toLowerCase();

    if (normalized.length.isOdd || RegExp(r'[^0-9a-f]').hasMatch(normalized)) {
      throw const FormatException('Invalid hex string.');
    }

    final bytes = <int>[];

    for (var i = 0; i < normalized.length; i += 2) {
      bytes.add(
        int.parse(normalized.substring(i, i + 2), radix: 16),
      );
    }

    return bytes;
  }

  static List<int> _hrpExpand(String hrp) {
    return [
      ...hrp.codeUnits.map((codeUnit) => codeUnit >> 5),
      0,
      ...hrp.codeUnits.map((codeUnit) => codeUnit & 31),
    ];
  }

  static int _polymod(List<int> values) {
    var checksum = 1;

    for (final value in values) {
      final top = checksum >> 25;
      checksum = ((checksum & 0x1ffffff) << 5) ^ value;

      for (var i = 0; i < 5; i++) {
        if (((top >> i) & 1) == 1) {
          checksum ^= _generators[i];
        }
      }
    }

    return checksum;
  }
}
