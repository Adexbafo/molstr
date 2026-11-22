import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class Nip05Verifier {
  Nip05Verifier._();
  static final Nip05Verifier instance = Nip05Verifier._();

  final _inFlight = <String, Future<bool>>{};

  Future<bool> verify(String identifier, String pubkeyHex) {
    final key = '${identifier.trim().toLowerCase()}|${pubkeyHex.toLowerCase()}';
    return _inFlight.putIfAbsent(
      key,
      () => _verify(key, identifier.trim(), pubkeyHex.toLowerCase()),
    );
  }

  Future<bool> _verify(String key, String identifier, String pubkeyHex) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('nip05v2.$key');

    if (cached != null) {
      try {
        final map = jsonDecode(cached) as Map<String, dynamic>;
        final ts = (map['ts'] as num?)?.toInt() ?? 0;
        final fresh = DateTime.now().millisecondsSinceEpoch - ts <
            const Duration(days: 7).inMilliseconds;
        if (fresh) return map['ok'] == true;
      } catch (_) {}
    }

    var ok = false;
    final at = identifier.lastIndexOf('@');

    if (at > 0 && at < identifier.length - 1) {
      final name = identifier.substring(0, at).toLowerCase();
      final domain = identifier.substring(at + 1).toLowerCase();
      try {
        final uri =
            Uri.https(domain, '/.well-known/nostr.json', {'name': name});
        final res = await http.get(uri).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          // NIP-05 returns the mapping under "names".
          final names = body is Map ? body['names'] : null;
          final value = names is Map ? names[name] : null;
          if (value is String) {
            ok = value.toLowerCase() == pubkeyHex;
          }
        }
      } catch (_) {}
    }

    await prefs.setString(
      'nip05v2.$key',
      jsonEncode({'ok': ok, 'ts': DateTime.now().millisecondsSinceEpoch}),
    );
    return ok;
  }
}
