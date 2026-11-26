// ignore_for_file: experimental_member_use
import 'package:ndk/shared/nips/nip04/nip04.dart' as nip04;
import 'package:ndk/shared/nips/nip44/nip44.dart' as nip44;

enum NwcEncryption {
  nip44V2,
  nip04;

  String get tagValue => this == NwcEncryption.nip44V2 ? 'nip44_v2' : 'nip04';
  String get storageValue => tagValue;
  String get label => this == NwcEncryption.nip44V2 ? 'NIP-44' : 'NIP-04';

  static NwcEncryption fromStorage(String? value) =>
      value == 'nip04' ? NwcEncryption.nip04 : NwcEncryption.nip44V2;
}

Future<String> encryptNwcContent({
  required String plaintext,
  required String secret,
  required String peerPubkey,
  required NwcEncryption mode,
}) {
  if (mode == NwcEncryption.nip04) {
    return Future.value(nip04.Nip04.encrypt(secret, peerPubkey, plaintext));
  }
  return nip44.Nip44.encryptMessage(plaintext, secret, peerPubkey);
}

/// Tries NIP-44 first, then NIP-04. Returns null if neither opens.
Future<String?> decryptNwcContent({
  required String payload,
  required String secret,
  required String peerPubkey,
}) async {
  try {
    return await nip44.Nip44.decryptMessage(payload, secret, peerPubkey);
  } catch (_) {}
  try {
    final plain = nip04.Nip04.decrypt(secret, peerPubkey, payload);
    if (plain.isNotEmpty) return plain;
  } catch (_) {}
  return null;
}
