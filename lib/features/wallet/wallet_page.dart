import 'package:flutter/material.dart';

import '../../core/nostr/identity_service.dart';
import '../../core/nostr/relay_service.dart';
import '../../core/payments/nwc.dart';
import '../../core/payments/nwc_cipher.dart';
import '../../core/payments/nwc_store.dart';
import 'monero_wallet_section.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({
    super.key,
    required this.identityService,
    required this.relayService,
    required this.relays,
  });

  final IdentityService identityService;
  final RelayService relayService;
  final List<String> relays;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final _store = NwcStore();
  final _uriController = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  NwcConnection? _connection;
  NwcEncryption _encryption = NwcEncryption.nip44V2;
  String? _info;
  String? _error;
  String? _balanceText;
  bool _canPay = false;
  DateTime? _statusAt;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _uriController.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _restore() async {
    final connection = await _store.load();
    final encryption = await _store.loadEncryption();
    if (!mounted) return;

    if (connection == null) {
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _connection = connection;
      _encryption = encryption;
      _loading = false;
    });

    await _checkStatus();
  }

  Future<void> _connect() async {
    if (_busy) return;
    final uri = _uriController.text.trim();

    if (uri.isEmpty) {
      setState(
          () => _error = 'Paste a nostr+walletconnect:// connection string.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final connection = NwcConnection.parse(uri);
      final info = await fetchWalletInfo(
        connection: connection,
        relayService: widget.relayService,
      );
      if (!mounted) return;

      if (info == null) {
        setState(() {
          _busy = false;
          _error = 'The wallet service did not answer. Nothing was saved.';
        });
        return;
      }

      await _store.save(uri);
      await _store.saveEncryption(NwcEncryption.nip44V2);
      if (!mounted) return;

      _uriController.clear();
      setState(() {
        _connection = connection;
        _encryption = NwcEncryption.nip44V2;
        _info = info;
        _busy = false;
      });
      _message('Wallet connected.');
      await _checkStatus();
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'Connection failed: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  Future<void> _checkStatus() async {
    final connection = _connection;
    if (connection == null || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final modes = <NwcEncryption>[
      _encryption,
      if (_encryption == NwcEncryption.nip44V2)
        NwcEncryption.nip04
      else
        NwcEncryption.nip44V2,
    ];

    for (final mode in modes) {
      NwcResponse? response;
      try {
        response = await walletGetInfo(
          connection: connection,
          relayService: widget.relayService,
          encryption: mode,
        );
      } catch (_) {
        response = null;
      }
      if (!mounted) return;
      if (response == null) continue;

      _encryption = mode;
      await _store.saveEncryption(mode);
      if (!mounted) return;

      if (!response.success) {
        final code = response.errorCode ?? 'unknown';
        final message = response.errorMessage;
        setState(() {
          _busy = false;
          _error = 'Wallet refused get_info: $code'
              '${message == null ? '' : ' — $message'}';
        });
        return;
      }

      final methods =
          (response.result['methods'] as List?)?.whereType<String>().toList() ??
              const <String>[];
      final canPay = methods.contains('pay_invoice');

      String? balanceText;
      if (methods.contains('get_balance')) {
        try {
          final balanceResponse = await walletGetBalance(
            connection: connection,
            relayService: widget.relayService,
            encryption: mode,
          );
          if (!mounted) return;
          if (balanceResponse != null && balanceResponse.success) {
            final raw = balanceResponse.result['balance'];
            final msats = raw is num ? raw.toInt() : int.tryParse('$raw');
            if (msats != null) {
              balanceText = msats % 1000 == 0
                  ? '${msats ~/ 1000} sats'
                  : '${(msats / 1000).toStringAsFixed(3)} sats';
            }
          }
        } catch (_) {
          balanceText = null;
        }
      }

      setState(() {
        _canPay = canPay;
        _info = methods.isEmpty ? '—' : 'Methods: ${methods.join(', ')}';
        _balanceText = balanceText;
        _statusAt = DateTime.now();
        _busy = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = 'The wallet did not answer in either encryption mode.';
    });
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect wallet?'),
        content: const Text(
          'MolStr will delete the connection secret from this device. '
          'Revoke it in your wallet too if you no longer trust this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _store.clear();
    if (!mounted) return;

    setState(() {
      _connection = null;
      _info = null;
      _error = null;
      _balanceText = null;
      _canPay = false;
      _statusAt = null;
    });
  }

  String _shortHex(String hex) {
    if (hex.length <= 20) return hex;
    return '${hex.substring(0, 10)}…${hex.substring(hex.length - 6)}';
  }

  Widget _buildLightning(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_connection == null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(Icons.bolt, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Connect a Nostr Wallet Connect (NWC) wallet',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Paste the connection string from your Lightning wallet. '
            'MolStr stores the secret only in secure storage.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _uriController,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            maxLines: 1,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'nostr+walletconnect://…',
              helperText: 'Spending credential — keep this private.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _connect,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link),
            label: Text(_busy ? 'Connecting…' : 'Connect wallet'),
          ),
        ],
      );
    }

    final connection = _connection!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text('Wallet connected',
                        style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Wallet service', style: theme.textTheme.labelSmall),
                SelectableText(
                  _shortHex(connection.walletPubkey),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text('Relay', style: theme.textTheme.labelSmall),
                for (final relay in connection.relays)
                  Text(relay, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Text('Encryption', style: theme.textTheme.labelSmall),
                Text(_encryption.label, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Text('Can pay invoices', style: theme.textTheme.labelSmall),
                Text(_canPay ? 'Yes' : 'Not confirmed yet',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Text('Wallet info', style: theme.textTheme.labelSmall),
                SelectableText(_info ?? '—', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
        if (_balanceText != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.bolt),
              title: Text('Balance: $_balanceText'),
            ),
          ),
        ],
        if (_statusAt != null) ...[
          const SizedBox(height: 8),
          Text('Status checked just now.', style: theme.textTheme.bodySmall),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _checkStatus,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: Text(_busy ? 'Checking…' : 'Check wallet status'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _disconnect,
          icon: const Icon(Icons.link_off),
          label: const Text('Disconnect'),
        ),
        const SizedBox(height: 12),
        Text(
          'MolStr contacts your wallet only when you press a button here '
          'or confirm a zap. It never pays without your confirmation.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.bolt), text: 'Lightning'),
                Tab(icon: Icon(Icons.lock_outline), text: 'Monero'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildLightning(context),
                  MoneroWalletSection(
                    identityService: widget.identityService,
                    relayService: widget.relayService,
                    relays: widget.relays,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
