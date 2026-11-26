import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/nostr/identity_service.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/relay_service.dart';
import '../../core/payments/lnurl.dart';
import '../../core/payments/nwc.dart';
import '../../core/payments/nwc_cipher.dart';
import '../../core/payments/nwc_store.dart';
import '../../core/payments/zap_service.dart';

Future<void> showZapSheet({
  required BuildContext context,
  required String recipientName,
  required String recipientLud16,
  required String recipientPubkeyHex,
  required NostrEvent? noteEvent,
  required List<String> relays,
  required IdentityService identityService,
  required RelayService relayService,
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
      relayService: relayService,
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
    required this.relayService,
  });

  final String recipientName;
  final String recipientLud16;
  final String recipientPubkeyHex;
  final NostrEvent? noteEvent;
  final List<String> relays;
  final IdentityService identityService;
  final RelayService relayService;

  @override
  State<ZapSheet> createState() => _ZapSheetState();
}

class _ZapSheetState extends State<ZapSheet> {
  final _amountController = TextEditingController(text: '100');
  final _commentController = TextEditingController();
  final _nwcStore = NwcStore();

  static const _presets = [21, 100, 500, 1000, 5000];

  String _phase = 'form';
  String _status = '';
  String _error = '';
  String _invoice = '';
  int _sats = 0;

  NwcConnection? _walletConnection;
  NwcEncryption _walletEncryption = NwcEncryption.nip44V2;
  bool _walletLoading = true;
  bool _payingWallet = false;
  bool _walletPaid = false;
  String? _walletStatus;

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadWallet() async {
    try {
      final connection = await _nwcStore.load();
      final encryption = await _nwcStore.loadEncryption();

      if (!mounted) return;

      setState(() {
        _walletConnection = connection;
        _walletEncryption = encryption;
        _walletLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _walletConnection = null;
        _walletLoading = false;
      });
    }
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

      setState(() {
        _status = 'Signing zap request…';
      });

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

      setState(() {
        _status = 'Requesting invoice…';
      });

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
        _payingWallet = false;
        _walletPaid = false;
        _walletStatus = null;
      });
    } on FormatException catch (error) {
      if (!mounted) return;

      setState(() {
        _phase = 'error';
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _phase = 'error';
        _error =
            'Zap failed: ${error.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  Future<void> _payWithWallet() async {
    final connection = _walletConnection;

    if (connection == null || _payingWallet || _walletPaid) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pay $_sats sats?'),
        content: Text(
          'Pay ${widget.recipientName} using your connected wallet?\n\n'
          'Recipient: ${widget.recipientLud16}\n'
          'Amount: $_sats sats\n\n'
          'This zap is public and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Pay'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _payingWallet = true;
      _walletStatus = 'Sending payment request to your wallet…';
    });

    try {
      final response = await walletPayInvoice(
        connection: connection,
        relayService: widget.relayService,
        invoice: _invoice,
        encryption: _walletEncryption,
      );

      if (!mounted) return;

      if (response == null) {
        setState(() {
          _walletStatus =
              'Payment status unknown. The wallet did not answer within '
              '45 seconds. Do not retry yet—check your wallet history first.';
        });
      } else if (!response.success) {
        setState(() {
          _walletStatus = 'Wallet refused payment: '
              '${response.errorCode ?? 'unknown'}'
              '${response.errorMessage == null ? '' : ' — ${response.errorMessage}'}';
        });
      } else {
        setState(() {
          _walletPaid = true;
          _walletStatus =
              'Paid via connected wallet. The zap receipt may take a '
              'moment to appear on your relays.';
        });
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _walletStatus = 'Payment request failed: '
            '${error.toString().replaceFirst('Exception: ', '')}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _payingWallet = false;
        });
      }
    }
  }

  Future<void> _copyInvoice() async {
    await Clipboard.setData(ClipboardData(text: _invoice));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invoice copied.')),
    );
  }

  Future<void> _openWallet() async {
    try {
      final opened = await launchUrl(
        Uri.parse('lightning:$_invoice'),
        mode: LaunchMode.externalApplication,
      );

      if (!opened && mounted) {
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
              Text(
                'Zap ${widget.recipientName}',
                style: textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                widget.recipientLud16,
                style: textTheme.bodySmall,
              ),
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
                      onSelected: (_) {
                        setState(() {
                          _amountController.text = '$preset';
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
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
              Text(
                'Pay $_sats sats in your wallet',
                style: textTheme.titleLarge,
              ),
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
              SelectableText(
                _invoice,
                style: const TextStyle(fontSize: 11),
              ),
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
              if (_walletLoading) ...[
                const SizedBox(height: 12),
                const Text('Checking for a connected wallet…'),
              ],
              if (!_walletLoading && _walletConnection != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _payingWallet || _walletPaid ? null : _payWithWallet,
                    icon: _payingWallet
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.account_balance_wallet_outlined),
                    label: Text(
                      _payingWallet
                          ? 'Paying…'
                          : _walletPaid
                              ? 'Paid with connected wallet'
                              : 'Pay $_sats sats with connected wallet',
                    ),
                  ),
                ),
                if (_walletStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(_walletStatus!),
                ],
              ],
              if (!_walletLoading && _walletConnection == null) ...[
                const SizedBox(height: 12),
                const Text(
                  'No NWC wallet connected. Connect one in Wallet, or use '
                  'Open wallet / Copy invoice.',
                ),
              ],
              const SizedBox(height: 12),
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
                      onPressed: () {
                        setState(() {
                          _phase = 'form';
                        });
                      },
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
