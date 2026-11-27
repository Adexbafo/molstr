import 'package:flutter/material.dart';

import '../../core/nostr/relay_service.dart';
import '../../core/payments/nwc.dart';
import '../../core/payments/nwc_cipher.dart';
import '../../core/payments/nwc_store.dart';

/// The Lightning side of the Wallet: one Nostr Wallet Connect connection.
///
/// Connecting sends an encrypted, read-only get_info request, so a
/// connection string is saved only after the wallet has answered it.
/// Nothing here contacts the wallet until the user presses a button.
class WalletPage extends StatefulWidget {
  const WalletPage({super.key, required this.relayService});

  final RelayService relayService;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

/// The outcome of asking the wallet for get_info.
class _Probe {
  const _Probe({this.mode, this.response, this.failure});

  final NwcEncryption? mode;
  final NwcResponse? response;
  final String? failure;
}

class _WalletPageState extends State<WalletPage> {
  final _store = NwcStore();
  final _uriController = TextEditingController();

  bool _restoring = true;
  bool _busy = false;
  String _busyText = '';

  NwcConnection? _connection;
  NwcEncryption _encryption = NwcEncryption.nip44V2;
  List<String>? _methods;
  String? _balanceText;
  String? _notice;
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

  String _clean(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  String _shortHex(String hex) {
    if (hex.length <= 20) return hex;
    return '${hex.substring(0, 10)}…${hex.substring(hex.length - 6)}';
  }

  String? _formatBalance(Object? raw) {
    final msats = raw is num ? raw.toInt() : int.tryParse('$raw');
    if (msats == null) return null;
    if (msats % 1000 == 0) return '${msats ~/ 1000} sats';
    return '${(msats / 1000).toStringAsFixed(3)} sats';
  }

  List<String>? _methodsFrom(NwcResponse response) {
    if (!response.success) return null;
    final raw = response.result['methods'];
    if (raw is! List) return null;
    return raw.whereType<String>().toList();
  }

  /// Reads the saved connection from secure storage. No network is used.
  Future<void> _restore() async {
    NwcConnection? connection;
    var encryption = NwcEncryption.nip44V2;
    String? error;

    try {
      connection = await _store.load();
      encryption = await _store.loadEncryption();
    } catch (_) {
      error = 'Could not open secure storage, so MolStr cannot tell whether '
          'a wallet is saved. Unlock your keyring and reopen the app.';
    }

    if (!mounted) return;
    setState(() {
      _connection = connection;
      _encryption = encryption;
      _error = error;
      _restoring = false;
    });
  }

  /// Sends an encrypted get_info request. It is read-only and spends
  /// nothing. Tries [preferred] first, then the other encryption mode.
  Future<_Probe> _probe(
    NwcConnection connection,
    NwcEncryption preferred,
  ) async {
    final modes = [
      preferred,
      for (final mode in NwcEncryption.values)
        if (mode != preferred) mode,
    ];

    String? failure;
    for (final mode in modes) {
      try {
        final response = await sendNwcRequest(
          connection: connection,
          relayService: widget.relayService,
          method: 'get_info',
          encryption: mode,
          overallTimeout: const Duration(seconds: 15),
        );
        if (response != null) {
          return _Probe(mode: mode, response: response);
        }
      } catch (error) {
        failure = 'Could not reach the wallet: ${_clean(error)} '
            'Check your connection and that this device\'s clock is correct.';
      }
    }
    return _Probe(failure: failure);
  }

  Future<void> _connect() async {
    if (_busy) return;

    final uri = _uriController.text.trim();
    final NwcConnection connection;
    try {
      connection = NwcConnection.parse(uri);
    } on FormatException catch (error) {
      setState(() {
        _error = error.message;
      });
      return;
    }

    setState(() {
      _busy = true;
      _busyText = 'Asking the wallet to confirm this connection…';
      _error = null;
      _notice = null;
    });

    final probe = await _probe(connection, NwcEncryption.nip44V2);
    if (!mounted) return;

    final response = probe.response;
    final mode = probe.mode;

    if (response == null || mode == null) {
      setState(() {
        _busy = false;
        _error = '${probe.failure ?? 'The wallet did not answer.'} '
            'Nothing was saved.';
      });
      return;
    }

    if (response.errorCode == 'UNAUTHORIZED') {
      setState(() {
        _busy = false;
        _error = 'The wallet does not recognise this connection string. '
            'Nothing was saved.';
      });
      return;
    }

    try {
      await _store.saveEncryption(mode);
      await _store.save(uri);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save to secure storage. Nothing was saved.';
      });
      return;
    }

    if (!mounted) return;
    _uriController.clear();
    setState(() {
      _busy = false;
      _connection = connection;
      _encryption = mode;
      _methods = _methodsFrom(response);
      _balanceText = null;
      _notice = response.success
          ? 'Connection confirmed by the wallet.'
          : 'The wallet accepted this connection but did not share its '
              'details (${response.errorCode ?? 'no reason given'}).';
    });
  }

  /// Asks the wallet for its current details and balance.
  Future<void> _refresh() async {
    final connection = _connection;
    if (connection == null || _busy) return;

    setState(() {
      _busy = true;
      _busyText = 'Asking the wallet for its status…';
      _error = null;
      _notice = null;
    });

    final probe = await _probe(connection, _encryption);
    if (!mounted) return;

    final response = probe.response;
    final mode = probe.mode;

    if (response == null || mode == null) {
      setState(() {
        _busy = false;
        _error =
            probe.failure ?? 'The wallet did not answer. It may be offline.';
      });
      return;
    }

    if (response.errorCode == 'UNAUTHORIZED') {
      setState(() {
        _busy = false;
        _error = 'The wallet no longer recognises this connection. It may '
            'have been revoked. Disconnect, then connect again.';
      });
      return;
    }

    if (mode != _encryption) {
      try {
        await _store.saveEncryption(mode);
      } catch (_) {
        // The mode is still used for this session.
      }
      if (!mounted) return;
    }

    final methods = _methodsFrom(response);
    String? balanceText;
    String? balanceProblem;

    if (methods == null || methods.contains('get_balance')) {
      setState(() {
        _busyText = 'Asking the wallet for its balance…';
      });
      try {
        final balance = await walletGetBalance(
          connection: connection,
          relayService: widget.relayService,
          encryption: mode,
        );
        if (balance == null) {
          balanceProblem = 'The wallet did not answer the balance request.';
        } else if (!balance.success) {
          balanceProblem = 'The wallet did not share its balance '
              '(${balance.errorCode ?? 'no reason given'}).';
        } else {
          balanceText = _formatBalance(balance.result['balance']);
          if (balanceText == null) {
            balanceProblem =
                'The wallet returned a balance MolStr could not read.';
          }
        }
      } catch (error) {
        balanceProblem = 'Balance request failed: ${_clean(error)}';
      }
      if (!mounted) return;
    }

    setState(() {
      _busy = false;
      _encryption = mode;
      _methods = methods ?? _methods;
      _balanceText = balanceText;
      _error = balanceProblem;
      _notice = 'Status checked just now.';
    });
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect wallet?'),
        content: const Text(
          'MolStr will delete the connection secret from this device. To '
          'cancel the connection completely, also revoke it in your wallet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _store.clear();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not delete the secret from secure storage.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _connection = null;
      _methods = null;
      _balanceText = null;
      _notice = null;
      _error = null;
    });
  }

  Widget _busyRow() {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(_busyText)),
      ],
    );
  }

  String _canPayText() {
    final methods = _methods;
    if (methods == null) {
      return 'Not checked yet. Press "Check wallet status".';
    }
    if (methods.contains('pay_invoice')) return 'Yes';
    return 'No. This connection is not allowed to pay.';
  }

  List<Widget> _connectForm(ThemeData theme) {
    return [
      Icon(Icons.bolt, size: 48, color: theme.colorScheme.primary),
      const SizedBox(height: 12),
      Text(
        'Connect a Lightning wallet',
        style: theme.textTheme.titleLarge,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      const Text(
        'Paste the Nostr Wallet Connect string from your wallet. MolStr asks '
        'the wallet to confirm it before saving anything. The secret is kept '
        'in this device\'s secure storage. Spending limits are set in your '
        'wallet, not in MolStr.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
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
          helperText: 'Spending credential. Keep this private.',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      if (_error != null) ...[
        Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        const SizedBox(height: 12),
      ],
      if (_busy) ...[
        _busyRow(),
        const SizedBox(height: 12),
      ],
      FilledButton.icon(
        onPressed: _busy ? null : _connect,
        icon: const Icon(Icons.link),
        label: const Text('Connect wallet'),
      ),
    ];
  }

  List<Widget> _connectedView(ThemeData theme, NwcConnection connection) {
    final textTheme = theme.textTheme;

    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text('Wallet connected', style: textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 12),
              Text('Wallet service', style: textTheme.labelSmall),
              Text(
                _shortHex(connection.walletPubkey),
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text('Relay', style: textTheme.labelSmall),
              for (final relay in connection.relays)
                Text(relay, style: textTheme.bodySmall),
              const SizedBox(height: 8),
              Text('Encryption', style: textTheme.labelSmall),
              Text(_encryption.label, style: textTheme.bodySmall),
              const SizedBox(height: 8),
              Text('Can pay invoices', style: textTheme.labelSmall),
              Text(_canPayText(), style: textTheme.bodySmall),
            ],
          ),
        ),
      ),
      if (_balanceText != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.bolt, size: 18),
                const SizedBox(width: 8),
                Text('Balance: $_balanceText', style: textTheme.titleSmall),
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
      if (_notice != null) ...[
        Text(_notice!, style: textTheme.bodySmall),
        const SizedBox(height: 8),
      ],
      if (_error != null) ...[
        Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        const SizedBox(height: 8),
      ],
      if (_busy) ...[
        _busyRow(),
        const SizedBox(height: 8),
      ],
      FilledButton.icon(
        onPressed: _busy ? null : _refresh,
        icon: const Icon(Icons.refresh),
        label: const Text('Check wallet status'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy ? null : _disconnect,
        icon: const Icon(Icons.link_off),
        label: const Text('Disconnect'),
      ),
      const SizedBox(height: 12),
      Text(
        'MolStr contacts your wallet only when you press a button here or '
        'confirm a zap. It never pays without your confirmation.',
        style: textTheme.bodySmall,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connection = _connection;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_restoring) const Center(child: CircularProgressIndicator()),
            if (!_restoring && connection == null) ..._connectForm(theme),
            if (!_restoring && connection != null)
              ..._connectedView(theme, connection),
          ],
        ),
      ),
    );
  }
}
