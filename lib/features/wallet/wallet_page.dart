import 'package:flutter/material.dart';

import '../../core/nostr/relay_service.dart';
import '../../core/payments/nwc.dart';
import '../../core/payments/nwc_cipher.dart';
import '../../core/payments/nwc_store.dart';

enum WalletPhase { loading, disconnected, connected, connecting, error }

class WalletPage extends StatefulWidget {
  const WalletPage({super.key, required this.relayService});

  final RelayService relayService;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final _store = NwcStore();
  final _uriController = TextEditingController();

  WalletPhase _phase = WalletPhase.loading;
  NwcConnection? _connection;
  NwcEncryption _encryption = NwcEncryption.nip44V2;
  String? _info;
  String? _error;
  String? _testInfo;
  String? _balanceText;
  bool _checkingBalance = false;

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
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _restore() async {
    final connection = await _store.load();
    final enc = await _store.loadEncryption();
    if (!mounted) {
      return;
    }
    if (connection == null) {
      setState(() {
        _phase = WalletPhase.disconnected;
      });
      return;
    }
    setState(() {
      _connection = connection;
      _encryption = enc;
      _phase = WalletPhase.connected;
    });
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
      setState(() {
        _connection = connection;
      });
      final info = await fetchWalletInfo(
        connection: connection,
        relayService: widget.relayService,
      );
      if (!mounted) {
        return;
      }
      if (info == null) {
        setState(() {
          _phase = WalletPhase.error;
          _error =
              'The wallet service did not answer on its relays. Nothing was saved.';
        });
        return;
      }
      await _store.save(uri);
      await _store.saveEncryption(NwcEncryption.nip44V2);
      if (!mounted) {
        return;
      }
      _uriController.clear();
      setState(() {
        _phase = WalletPhase.connected;
        _info = info;
        _encryption = NwcEncryption.nip44V2;
        _testInfo = null;
        _balanceText = null;
      });
      _message('Wallet connected.');
    } on FormatException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = WalletPhase.error;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = WalletPhase.error;
        _error =
            'Connection failed: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  Future<void> _handshake({required bool showErrors}) async {
    final connection = _connection;
    if (connection == null) {
      return;
    }
    setState(() {
      _phase = WalletPhase.connecting;
    });
    try {
      final info = await fetchWalletInfo(
        connection: connection,
        relayService: widget.relayService,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = WalletPhase.connected;
        _info = info;
        if (info == null && showErrors) {
          _error = 'The wallet service did not answer on its relays.';
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = WalletPhase.connected;
        if (showErrors) {
          _error =
              'Handshake failed: ${e.toString().replaceFirst('Exception: ', '')}';
        }
      });
    }
  }

  Future<void> _testConnection() async {
    final connection = _connection;
    if (connection == null || _phase == WalletPhase.connecting) {
      return;
    }
    setState(() {
      _phase = WalletPhase.connecting;
      _error = null;
      _testInfo = null;
    });
    for (final mode in [NwcEncryption.nip44V2, NwcEncryption.nip04]) {
      try {
        final response = await walletGetInfo(
          connection: connection,
          relayService: widget.relayService,
          encryption: mode,
        );
        if (!mounted) {
          return;
        }
        if (response == null) {
          continue;
        }
        if (!response.success) {
          await _store.saveEncryption(mode);
          setState(() {
            _phase = WalletPhase.connected;
            _encryption = mode;
            _error =
                'Wallet refused get_info: ${response.errorCode ?? 'unknown'}${response.errorMessage == null ? '' : ' — ${response.errorMessage}'}';
          });
          return;
        }
        await _store.saveEncryption(mode);
        final methods = (response.result['methods'] as List?)
                ?.whereType<String>()
                .join(', ') ??
            'none advertised';
        setState(() {
          _phase = WalletPhase.connected;
          _encryption = mode;
          _error = null;
          _testInfo =
              'Encrypted request round-trip confirmed (${mode.label}).\nMethods: $methods';
        });
        return;
      } catch (_) {
        continue;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _phase = WalletPhase.connected;
      _error = 'The wallet did not answer within 60 seconds in either mode.';
    });
  }

  Future<void> _checkBalance() async {
    final connection = _connection;
    if (connection == null ||
        _checkingBalance ||
        _phase == WalletPhase.connecting) {
      return;
    }
    setState(() {
      _checkingBalance = true;
      _error = null;
    });
    try {
      final response = await walletGetBalance(
        connection: connection,
        relayService: widget.relayService,
        encryption: _encryption,
      );
      if (!mounted) {
        return;
      }
      if (response == null) {
        setState(() {
          _balanceText = null;
          _error =
              'The wallet did not answer the balance request within 30 seconds.';
        });
        return;
      }
      if (!response.success) {
        setState(() {
          _balanceText = null;
          _error =
              'Wallet refused get_balance: ${response.errorCode ?? 'unknown'}';
        });
        return;
      }
      final raw = response.result['balance'];
      final msats = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (msats == null) {
        setState(() {
          _balanceText = null;
          _error = 'Wallet returned a balance MolStr could not read.';
        });
        return;
      }
      setState(() {
        _balanceText = msats % 1000 == 0
            ? '${msats ~/ 1000} sats'
            : '${(msats / 1000).toStringAsFixed(3)} sats';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _balanceText = null;
        _error =
            'Balance request failed: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _checkingBalance = false;
        });
      }
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect wallet?'),
        content: const Text(
          'MolStr will delete the connection secret from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _store.clear();
    if (!mounted) {
      return;
    }
    setState(() {
      _connection = null;
      _info = null;
      _phase = WalletPhase.disconnected;
      _testInfo = null;
      _balanceText = null;
    });
  }

  String _shortHex(String hex) {
    if (hex.length <= 20) {
      return hex;
    }
    return '${hex.substring(0, 10)}…${hex.substring(hex.length - 6)}';
  }

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
                if (_error != null) ...[
                  Text(_error!),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Connect a Nostr Wallet Connect (NWC) wallet',
                  style: theme.textTheme.titleLarge,
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
                  icon: const Icon(Icons.link),
                  label: const Text('Connect wallet'),
                ),
              ],
              if (_phase == WalletPhase.connecting) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 16),
                const Text(
                  'Checking wallet service…',
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
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Wallet connected',
                              style: theme.textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Service public key',
                          style: theme.textTheme.labelSmall,
                        ),
                        SelectableText(
                          _shortHex(_connection!.walletPubkey),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text('Relays', style: theme.textTheme.labelSmall),
                        for (final relay in _connection!.relays)
                          Text(relay, style: theme.textTheme.bodySmall),
                        const SizedBox(height: 8),
                        Text(
                          'Encryption: ${_encryption.label}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Wallet info',
                          style: theme.textTheme.labelSmall,
                        ),
                        SelectableText(
                          _info ?? '—',
                          style: theme.textTheme.bodySmall,
                        ),
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
                if (_testInfo != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _testInfo!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                if (_balanceText != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Wallet balance: $_balanceText',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _phase == WalletPhase.connecting
                      ? null
                      : () {
                          _handshake(showErrors: true);
                        },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Re-check wallet'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed:
                      _phase == WalletPhase.connecting ? null : _testConnection,
                  icon: const Icon(Icons.security_outlined),
                  label: const Text('Test encrypted connection (get_info)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed:
                      _checkingBalance || _phase == WalletPhase.connecting
                          ? null
                          : _checkBalance,
                  icon: _checkingBalance
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.account_balance_outlined),
                  label: Text(
                    _checkingBalance ? 'Checking balance…' : 'Check balance',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
