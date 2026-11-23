import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/nostr/identity_service.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/payments/lnurl.dart';
import '../../core/payments/zap_service.dart';

Future<void> showZapSheet({
  required BuildContext context,
  required String recipientName,
  required String recipientLud16,
  required String recipientPubkeyHex,
  required NostrEvent? noteEvent,
  required List<String> relays,
  required IdentityService identityService,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ZapSheet(
      recipientName: recipientName,
      recipientLud16: recipientLud16,
      recipientPubkeyHex: recipientPubkeyHex,
      noteEvent: noteEvent,
      relays: relays,
      identityService: identityService,
    ),
  );
}

class ZapSheet extends StatefulWidget {
  const ZapSheet({
    super.key,
    required this.recipientName,
    required this.recipientLud16,
    required this.recipientPubkeyHex,
    required this.noteEvent,
    required this.relays,
    required this.identityService,
  });

  final String recipientName;
  final String recipientLud16;
  final String recipientPubkeyHex;
  final NostrEvent? noteEvent;
  final List<String> relays;
  final IdentityService identityService;

  @override
  State<ZapSheet> createState() => _ZapSheetState();
}

class _ZapSheetState extends State<ZapSheet> {
  final _amountController = TextEditingController(text: '100');
  final _commentController = TextEditingController();
  final _presets = const [21, 100, 500, 1000, 5000];

  String _phase = 'form';
  String _status = '';
  String _error = '';
  String _invoice = '';
  int _sats = 0;

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _startZap() async {
    final sats = int.tryParse(_amountController.text.trim());
    if (sats == null || sats <= 0) {
      setState(() {
        _phase = 'error';
        _error = 'Enter an amount in sats greater than zero.';
      });
      return;
    }
    final comment = _commentController.text.trim();
    setState(() {
      _phase = 'loading';
      _status = 'Resolving ${widget.recipientLud16}…';
      _error = '';
    });
    try {
      final address = LightningAddress.parse(widget.recipientLud16);
      final params = await fetchLnurlPayParams(address);
      if (!params.allowsNostr) {
        throw const FormatException(
          'This Lightning address does not support Nostr zaps.',
        );
      }
      final amountMsats = satsToMsats(sats);
      validateAmountMsats(amountMsats, params);
      if (!mounted) return;
      setState(() => _status = 'Signing zap request…');
      final tags = buildZapRequestTags(
        recipientPubkeyHex: widget.recipientPubkeyHex,
        amountMsats: amountMsats,
        relays: widget.relays,
        eventId: widget.noteEvent?.id,
      );
      final zapRequest = await widget.identityService.signEvent(
        kind: 9734,
        content: comment,
        tags: tags,
      );
      if (!mounted) return;
      setState(() => _status = 'Requesting invoice…');
      final invoice = await fetchZapInvoice(
        params: params,
        zapRequest: zapRequest,
        amountMsats: amountMsats,
      );
      if (!mounted) return;
      setState(() {
        _phase = 'invoice';
        _invoice = invoice;
        _sats = sats;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = 'error';
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = 'error';
        _error = 'Zap failed: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  Future<void> _copyInvoice() async {
    await Clipboard.setData(ClipboardData(text: _invoice));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Invoice copied.')));
  }

  Future<void> _openWallet() async {
    try {
      final ok = await launchUrl(
        Uri.parse('lightning:$_invoice'),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No Lightning wallet found. Copy the invoice.'),
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_phase == 'form') ...[
              Text('Zap ${widget.recipientName}',
                  style: textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(widget.recipientLud16, style: textTheme.bodySmall),
              if (widget.noteEvent != null) ...[
                const SizedBox(height: 8),
                Text(
                  widget.noteEvent!.content.length > 120
                      ? '${widget.noteEvent!.content.substring(0, 120)}…'
                      : widget.noteEvent!.content,
                  style: textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final preset in _presets)
                    ChoiceChip(
                      label: Text('$preset'),
                      selected: _amountController.text.trim() == '$preset',
                      onSelected: (_) => setState(
                        () => _amountController.text = '$preset',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Amount (sats)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _commentController,
                maxLines: 2,
                maxLength: 140,
                decoration: const InputDecoration(
                  labelText: 'Comment (optional, public)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Zaps are public. Resolving the address reveals your IP to '
                'the recipient server.',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _startZap,
                  icon: const Icon(Icons.bolt),
                  label: const Text('Get Lightning invoice'),
                ),
              ),
            ],
            if (_phase == 'loading') ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              Center(child: Text(_status)),
            ],
            if (_phase == 'invoice') ...[
              Text('Pay $_sats sats in your wallet',
                  style: textTheme.titleLarge),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: QrImageView(
                    data: _invoice,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(_invoice, style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyInvoice,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _openWallet,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open wallet'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'After paying, the server should publish a zap receipt. '
                'Receipt tracking arrives later.',
                style: textTheme.bodySmall,
              ),
            ],
            if (_phase == 'error') ...[
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(_error),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _phase = 'form'),
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _startZap,
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
