bool isValidMoneroAddress(String address) {
  final trimmed = address.trim();
  if (trimmed.length != 95 && trimmed.length != 106) return false;
  if (!trimmed.startsWith('4') && !trimmed.startsWith('8')) return false;
  final base58 = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');
  return base58.hasMatch(trimmed);
}

String normalizeXmrAmount(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Enter an amount.');
  }
  final regex = RegExp(r'^(0|[1-9]\d*)(\.\d{1,12})?$');
  if (!regex.hasMatch(trimmed)) {
    throw const FormatException('Enter XMR like 0.1 (up to 12 decimals).');
  }
  final parts = trimmed.split('.');
  final whole = int.parse(parts[0]);
  final frac = parts.length > 1 ? parts[1] : '';
  final hasNonZeroFrac = frac.contains(RegExp(r'[1-9]'));
  if (whole == 0 && !hasNonZeroFrac) {
    throw const FormatException('Amount must be greater than zero.');
  }
  if (parts.length == 1) return parts[0];
  var f = frac;
  while (f.endsWith('0')) {
    f = f.substring(0, f.length - 1);
  }
  if (f.isEmpty) return parts[0];
  return '${parts[0]}.$f';
}

String buildMoneroUri({
  required String address,
  String? amountXmr,
  String? description,
}) {
  final trimmedAddr = address.trim();
  if (!isValidMoneroAddress(trimmedAddr)) {
    throw const FormatException('Invalid Monero address.');
  }
  String? normalizedAmount;
  if (amountXmr != null && amountXmr.trim().isNotEmpty) {
    normalizedAmount = normalizeXmrAmount(amountXmr);
  }
  final desc = description?.trim() ?? '';
  if (desc.length > 200) {
    throw const FormatException('Description too long (max 200).');
  }
  final query = <String, String>{};
  if (normalizedAmount != null) query['tx_amount'] = normalizedAmount;
  if (desc.isNotEmpty) query['tx_description'] = desc;
  final uri = Uri(
    scheme: 'monero',
    path: trimmedAddr,
    queryParameters: query.isEmpty ? null : query,
  );
  return uri.toString();
}
