import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'identity_service.dart';

class BlossomUpload {
  static Future<String> upload({
    required List<int> bytes,
    required String filename,
    required String mimeType,
    required String server,
    required IdentityService identityService,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final sha = sha256.convert(bytes).toString();
    final expiration =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
            1000;

    final authEvent = await identityService.signEvent(
      kind: 24242,
      content: 'MolStr upload',
      tags: [
        ['t', 'upload'],
        ['x', sha],
        ['expiration', '$expiration'],
      ],
    );

    final auth = base64Encode(utf8.encode(jsonEncode(authEvent.toJson())));
    final serverUri = Uri.tryParse(server.trim());
    if (serverUri == null ||
        !serverUri.hasAuthority ||
        serverUri.host.isEmpty) {
      throw const FormatException('Invalid Blossom server URL.');
    }

    final scheme = serverUri.scheme.toLowerCase();
    final host = serverUri.host.toLowerCase();
    final isLoopback =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';

    if (scheme != 'https' && !(scheme == 'http' && isLoopback)) {
      throw const FormatException(
        'Remote Blossom servers must use https.',
      );
    }

    final base =
        server.trim().endsWith('/') ? server.trim() : '${server.trim()}/';
    final endpoint = Uri.parse(base).resolve('upload');

    final res = await http
        .put(
          endpoint,
          headers: {
            'Authorization': 'Nostr $auth',
            'Content-Type': mimeType,
          },
          body: bytes,
        )
        .timeout(timeout);

    if (res.statusCode != 200 && res.statusCode != 201) {
      final preview =
          res.body.length > 220 ? res.body.substring(0, 220) : res.body;
      throw Exception('Server returned ${res.statusCode}: $preview');
    }

    final data = jsonDecode(res.body);
    final url = data is Map ? data['url'] : null;

    if (url is String) {
      final mediaUri = Uri.tryParse(url);
      if (mediaUri != null &&
          mediaUri.hasAuthority &&
          mediaUri.scheme.toLowerCase() == 'https') {
        return url;
      }
    }

    throw Exception('Server did not return a secure media URL.');
  }
}
