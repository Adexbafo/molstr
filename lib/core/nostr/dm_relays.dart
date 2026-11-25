import 'nostr_event.dart';

/// NIP-17 DM relay list. Replaceable, so relays keep only the newest.
const int kDmRelayListKind = 10050;

/// Extracts wss:// relay URLs from a kind 10050 event.
/// Malformed, non-wss, and empty entries are dropped.
List<String> parseDmRelayList(NostrEvent event) {
  if (event.kind != kDmRelayListKind) return const [];

  final relays = <String>[];
  final seen = <String>{};

  for (final tag in event.tags) {
    if (tag.length < 2 || tag[0] != 'relay') continue;

    final value = tag[1].trim();
    if (value.isEmpty) continue;

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) continue;
    if (uri.scheme.toLowerCase() != 'wss') continue;
    if (uri.userInfo.isNotEmpty) continue;

    if (seen.add(value)) relays.add(value);
  }

  return relays;
}
