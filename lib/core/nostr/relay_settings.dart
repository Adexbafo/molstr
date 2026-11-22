import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

String normalizeRelayUrl(String input) {
  final value = input.trim();
  final uri = Uri.tryParse(value);

  if (uri == null ||
      uri.scheme != 'wss' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.hasPort && (uri.port < 1 || uri.port > 65535)) ||
      RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(value)) {
    throw const FormatException(
      'Use a wss:// relay URL without credentials, a query, or a fragment.',
    );
  }

  final url = uri.toString();
  // The root URL is the same with or without the final slash.
  // Leave custom paths intact.
  return uri.path == '/' && url.endsWith('/')
      ? url.substring(0, url.length - 1)
      : url;
}

class RelayConfig {
  const RelayConfig({
    required this.url,
    this.read = true,
    this.write = false,
  });

  final String url;
  final bool read;
  final bool write;

  RelayConfig copyWith({bool? read, bool? write}) => RelayConfig(
        url: url,
        read: read ?? this.read,
        write: write ?? this.write,
      );

  Map<String, Object> toJson() => {
        'url': url,
        'read': read,
        'write': write,
      };

  factory RelayConfig.fromJson(Map<String, dynamic> json) => RelayConfig(
        url: normalizeRelayUrl(json['url'] as String),
        read: json['read'] as bool,
        write: json['write'] as bool,
      );
}

class RelaySettingsStore {
  RelaySettingsStore(this._prefs);

  static const _key = 'molstr.relays.v1';
  final SharedPreferences _prefs;

  List<RelayConfig> load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];

    return [
      for (final row in jsonDecode(raw) as List<dynamic>)
        RelayConfig.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<void> save(List<RelayConfig> relays) async {
    final json = jsonEncode(relays.map((relay) => relay.toJson()).toList());
    final saved = await _prefs.setString(_key, json);
    if (!saved) throw StateError('Could not save relays.');
  }
}
