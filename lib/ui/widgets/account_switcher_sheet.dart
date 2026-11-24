import 'package:flutter/material.dart';

import '../../core/nostr/identity_service.dart';
import '../../features/onboarding/onboarding_page.dart';
import 'molstr_avatar.dart';

Future<bool?> showAccountSwitcherSheet({
  required BuildContext context,
  required IdentityService identityService,
  required Identity? activeIdentity,
  required VoidCallback onRefresh,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => AccountSwitcherSheet(
      identityService: identityService,
      activeIdentity: activeIdentity,
      onRefresh: onRefresh,
    ),
  );
}

class AccountSwitcherSheet extends StatefulWidget {
  const AccountSwitcherSheet({
    super.key,
    required this.identityService,
    required this.activeIdentity,
    required this.onRefresh,
  });

  final IdentityService identityService;
  final Identity? activeIdentity;
  final VoidCallback onRefresh;

  @override
  State<AccountSwitcherSheet> createState() => _AccountSwitcherSheetState();
}

class _AccountSwitcherSheetState extends State<AccountSwitcherSheet> {
  List<Identity> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await widget.identityService.listIdentities();
    if (mounted) {
      setState(() {
        _accounts = accounts;
        _loading = false;
      });
    }
  }

  String _shortNpub(String npub) {
    if (npub.length <= 16) return npub;
    return '${npub.substring(0, 10)}…${npub.substring(npub.length - 6)}';
  }

  Future<void> _switch(String pubkey) async {
    await widget.identityService.switchAccount(pubkey);
    widget.onRefresh();
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _signOut() async {
    await widget.identityService.signOut();
    widget.onRefresh();
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _removeAccount(String pubkey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove account?'),
        content: const Text(
          'This removes the private key for this account from this device. '
          'Ensure you have your nsec backed up.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.identityService.removeAccount(pubkey);
      widget.onRefresh();
      await _load();
    }
  }

  Future<void> _addAccount() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const OnboardingPage()),
    );
    if (added == true) {
      widget.onRefresh();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Accounts', style: theme.textTheme.titleLarge),
              FilledButton.icon(
                onPressed: _addAccount,
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Add Account'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No accounts stored on this device.')),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _accounts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final account = _accounts[index];
                  final isActive =
                      account.pubkey == widget.activeIdentity?.pubkey;

                  return Card(
                    color: isActive
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : null,
                    child: ListTile(
                      leading: MolStrAvatar(
                        name: account.npub,
                        picture: null,
                        loadImages: false,
                        radius: 18,
                      ),
                      title: Text(
                        _shortNpub(account.npub),
                        style: TextStyle(
                          fontWeight:
                              isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: isActive
                          ? Text('Active Account',
                              style:
                                  TextStyle(color: theme.colorScheme.primary))
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isActive)
                            OutlinedButton(
                              onPressed: () => _switch(account.pubkey),
                              child: const Text('Switch'),
                            ),
                          IconButton(
                            tooltip: 'Remove from device',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => _removeAccount(account.pubkey),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          if (widget.activeIdentity != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign Out (Disconnect active session)'),
              ),
            ),
        ],
      ),
    );
  }
}
