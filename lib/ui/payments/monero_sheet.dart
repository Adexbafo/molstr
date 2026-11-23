import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/payments/monero.dart';

Future<void> showMoneroSheet({
  required BuildContext context,
  required String recipientName,
  required String moneroAddress,
  String? notePreview,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => MoneroSheet(
      recipientName: recipientName,
      moneroAddress: moneroAddress,
      notePreview: notePreview,
    ),
  );
}

class MoneroSheet extends StatefulWidget {
  const MoneroSheet({
    super.key,
    required this.recipientName,
    required this.moneroAddress,
    this.notePreview,
  });

  final String recipientName;
  final String moneroAddress;
  final String? notePreview;

  @override
  State<MoneroSheet> createState() => _MoneroSheetState();
}

class _MoneroSheetState extends State<MoneroSheet> {
  final _amountController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copied.')));
  }

  Future<void> _openWallet(String uri) async {
    try {
      final ok = await launchUrl(
        Uri.parse(uri),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No Monero wallet found. Copy the address.'),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open a wallet.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final amountInput = _amountController.text.trim();
    String? amountError;
    if (amountInput.isNotEmpty) {
      try {
        normalizeXmrAmount(amountInput);
      } on FormatException catch (e) {
        amountError = e.message;
      }
    }

    String uri;
    try {
      uri = buildMoneroUri(
        address: widget.moneroAddress,
        amountXmr: amountInput.isEmpty ? null : amountInput,
        description:
            _descController.text.trim().isEmpty ? null : _descController.text,
      );
    } catch (_) {
      uri = 'monero:${widget.moneroAddress}';
    }
    final uriReady = amountError == null;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tip ${widget.recipientName} in Monero',
                style: textTheme.headlineSmall),
            const SizedBox(height: 8),
            SelectableText(widget.moneroAddress,
                style: const TextStyle(fontSize: 11)),
            if (widget.notePreview != null) ...[
              const SizedBox(height: 8),
              Text(widget.notePreview!, style: textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount (XMR, optional)',
                hintText: '0.1',
                errorText: amountError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QrImageView(
                  data: uri,
                  version: QrVersions.auto,
                  size: 180,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(uri, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _copy(widget.moneroAddress, 'Address'),
                    child: const Text('Copy address'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        uriReady ? () => _copy(uri, 'Payment link') : null,
                    child: const Text('Copy link'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: uriReady ? () => _openWallet(uri) : null,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in Monero wallet'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Private on-chain. MolStr only builds the link; it does not '
              'track payment.',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
