import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/nostr/relay_service.dart';
import '../../core/payments/nwc.dart';
import '../../core/payments/nwc_store.dart';

enum WalletPhase { loading, disconnected, connected, connecting, error }

class WalletPage extends StatefulWidget {
  const WalletPage({
    super.key,
    required this.relayService,
  });

  final RelayService relayService;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final _store = NwcStore();
  final _uriController = TextEditingController();

  WalletPhase _phase = WalletPhase.loading;
  NwcConnection? _connection;
  String? _info;
  String? _error;

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
    if (!mounted) return;
    if (connection == null) {
      setState(() => _phase = WalletPhase.disconnected);
      return;
    }
    setState(() {
      _connection = connection;
      _phase = WalletPhase.connected;
    });
    // Silent handshake refresh; failure keeps the saved connection.
    await _handshake(showErrors: false);
  }

  Future<void> _connect() async {
    final uri = _uriController.text.trim();
    if (uri.isEmpty) {
      setState(() {
        _phase = WalletPhase.error;
        _error = 'Paste a nostr+walletconnect:// connection string.';
      });
      return;
    }

    setState(() {
      _phase = WalletPhase.connecting;
      _error = null;
    });

    try {
      final connection = NwcConnection.parse(uri);
      setState(() => _connection = connection);

      // Handshake: prove the wallet is reachable before storing the secret.
      final info = await fetchWalletInfo(
        connection: connection,
        relayService: widget.relayService,
      );
      if (!mounted) return;

      if (info == null) {
        setState(() {
          _phase = WalletPhase.error;
          _error = 'The wallet service did not answer on its relays. '
              'Nothing was saved. Check that the wallet is online and try again.';
        });
        return;
      }

      await _store.save(uri);
      if (!mounted) return;
      _uriController.clear();
      setState(() {
        _phase = WalletPhase.connected;
        _info = info;
      });
      _message('Wallet connected.');
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = WalletPhase.error;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = WalletPhase.error;
        _error = 'Connection failed: '
            '${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  Future<void> _handshake({required bool showErrors}) async {
    final connection = _connection;
    if (connection == null) return;

    setState(() => _phase = WalletPhase.connecting);
    try {
      final info = await fetchWalletInfo(
        connection: connection,
        relayService: widget.relayService,
      );
      if (!mounted) return;
      setState(() {
        _phase = WalletPhase.connected;
        _info = info;
        if (showErrors && info == null) {
          _error = 'The wallet service did not answer on its relays.';
        } else if (info == null) {
          _error = 'The wallet service is not answering on its relays.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = WalletPhase.connected;
        if (showErrors) {
          _error = 'Handshake failed: '
              '${e.toString().replaceFirst('Exception: ', '')}';
        }
      });
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect wallet?'),
        content: const Text(
          'MolStr will delete the connection secret from this device. '
          'The wallet keeps working elsewhere until you revoke it in your '
          'wallet settings.',
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
      _phase = WalletPhase.disconnected;
    });
    _message('Wallet disconnected. Remember to revoke the connection in '
        'your wallet if needed.');
  }

  Future<void> _copyPubkey() async {
    final connection = _connection;
    if (connection == null) return;
    await Clipboard.setData(ClipboardData(text: connection.clientPubkey));
    _message('Client public key copied.');
  }

  String _shortHex(String hex) => hex.length <= 20
      ? hex
      : '${hex.substring(0, 10)}…${hex.substring(hex.length - 6)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_phase == WalletPhase.loading)
                const Center(child: CircularProgressIndicator()),
              if (_phase == WalletPhase.disconnected ||
                  _phase == WalletPhase.error) ...[
                Icon(
                  _phase == WalletPhase.error
                      ? Icons.error_outline
                      : Icons.account_balance_wallet_outlined,
                  size: 56,
                  color: _phase == WalletPhase.error
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Text(_error!, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Connect a Nostr Wallet Connect (NWC) wallet',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Paste the connection string from your Lightning wallet. '
                  'MolStr stores the secret only in this device\'s secure '
                  'storage and can only spend within the budget your wallet '
                  'grants.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _uriController,
                  enabled: _phase != WalletPhase.connecting,
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
                  onPressed: _phase == WalletPhase.connecting ? null : _connect,
                  icon: _phase == WalletPhase.connecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: Text(_phase == WalletPhase.connecting
                      ? 'Connecting…'
                      : 'Connect wallet'),
                ),
              ],
              if (_phase == WalletPhase.connecting && _connection != null) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 16),
                Text(
                  'Checking wallet service on '
                  '${_connection!.relays.length} relay(s)…',
                  textAlign: TextAlign.center,
                ),
              ],
              if (_phase == WalletPhase.connected && _connection != null) ...[
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
                        Text('Service public key',
                            style: theme.textTheme.labelSmall),
                        SelectableText(
                          _shortHex(_connection!.walletPubkey),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text('Client public key',
                            style: theme.textTheme.labelSmall),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _shortHex(_connection!.clientPubkey),
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy client public key',
                              icon: const Icon(Icons.copy, size: 16),
                              onPressed: _copyPubkey,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Relays', style: theme.textTheme.labelSmall),
                        for (final relay in _connection!.relays)
                          Text(relay, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                if (_info != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Wallet info (kind 13194)',
                              style: theme.textTheme.titleSmall),
                          const SizedBox(height: 8),
                          SelectableText(
                            _info!,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: _phase == WalletPhase.connecting
                      ? null
                      : () => _handshake(showErrors: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Re-check wallet'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Zaps on notes can be paid with this wallet once you '
                  'confirm the payment dialog. MolStr never spends without '
                  'your tap.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
