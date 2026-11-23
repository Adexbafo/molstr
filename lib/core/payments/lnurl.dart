import 'dart:convert';

import 'package:http/http.dart' as http;

class LightningAddress {
  const LightningAddress({required this.name, required this.domain});

  final String name;
  final String domain;

  static LightningAddress parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty ||
        trimmed.contains(' ') ||
        trimmed.contains('\n') ||
        trimmed.contains('\t')) {
      throw const FormatException(
        'Enter a Lightning address like name@domain.',
      );
    }
    final parts = trimmed.split('@');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      throw const FormatException(
        'Enter a Lightning address like name@domain.',
      );
    }
    final name = parts[0].trim();
    final domain = parts[1].trim().toLowerCase();
    if (name.isEmpty ||
        domain.isEmpty ||
        !domain.contains('.') ||
        domain.startsWith('.') ||
        domain.endsWith('.')) {
      throw const FormatException('Enter a valid Lightning address.');
    }
    return LightningAddress(name: name, domain: domain);
  }

  Uri get lnurlpUrl => Uri.https(domain, '/.well-known/lnurlp/$name');

  @override
  String toString() => '$name@$domain';
}

class LnurlPayParams {
  const LnurlPayParams({
    required this.callback,
    required this.minSendable,
    required this.maxSendable,
    required this.metadata,
    required this.allowsNostr,
    this.nostrPubkey,
  });

  final String callback;
  final int minSendable;
  final int maxSendable;
  final String metadata;
  final bool allowsNostr;
  final String? nostrPubkey;

  factory LnurlPayParams.fromJson(Map<String, dynamic> json) {
    final callback = json['callback'];
    final minRaw = json['minSendable'];
    final maxRaw = json['maxSendable'];
    final metadata = json['metadata'];
    if (callback is! String || callback.isEmpty) {
      throw const FormatException(
        'Invalid LNURL response (missing callback).',
      );
    }
    if (minRaw is! num || maxRaw is! num) {
      throw const FormatException('Invalid LNURL response (missing limits).');
    }
    if (metadata is! String) {
      throw const FormatException('Invalid LNURL response (missing metadata).');
    }
    final callbackUri = Uri.tryParse(callback);
    if (callbackUri == null || !callbackUri.hasAuthority) {
      throw const FormatException('Invalid LNURL callback URL.');
    }
    final scheme = callbackUri.scheme.toLowerCase();
    final host = callbackUri.host.toLowerCase();
    final isLoopback =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    if (scheme != 'https' && !(scheme == 'http' && isLoopback)) {
      throw const FormatException('LNURL callback must use https.');
    }
    final minSendable = minRaw.toInt();
    final maxSendable = maxRaw.toInt();
    if (minSendable <= 0 || maxSendable <= 0 || minSendable > maxSendable) {
      throw const FormatException('Invalid LNURL amount limits.');
    }
    final allowsNostr = json['allowsNostr'] == true;
    final nostrRaw = json['nostrPubkey'];
    final nostrPubkey =
        nostrRaw is String && nostrRaw.isNotEmpty ? nostrRaw : null;
    return LnurlPayParams(
      callback: callback,
      minSendable: minSendable,
      maxSendable: maxSendable,
      metadata: metadata,
      allowsNostr: allowsNostr,
      nostrPubkey: nostrPubkey,
    );
  }
}

Future<LnurlPayParams> fetchLnurlPayParams(LightningAddress address) async {
  final res =
      await http.get(address.lnurlpUrl).timeout(const Duration(seconds: 10));
  if (res.statusCode != 200) {
    throw Exception('Lightning address lookup failed (${res.statusCode}).');
  }
  try {
    final data = jsonDecode(res.body);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid LNURL response.');
    }
    return LnurlPayParams.fromJson(data);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Invalid LNURL response.');
  }
}

int satsToMsats(int sats) => sats * 1000;

void validateAmountMsats(int amountMsats, LnurlPayParams params) {
  if (amountMsats < params.minSendable) {
    final minSats = (params.minSendable / 1000).ceil();
    throw FormatException('Amount below minimum ($minSats sats).');
  }
  if (amountMsats > params.maxSendable) {
    final maxSats = (params.maxSendable / 1000).floor();
    throw FormatException('Amount above maximum ($maxSats sats).');
  }
}
