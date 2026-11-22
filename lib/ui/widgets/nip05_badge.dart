import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/nostr/nip05.dart';

class Nip05Badge extends StatefulWidget {
  const Nip05Badge({super.key, required this.identifier, required this.pubkey});
  final String identifier;
  final String pubkey;

  @override
  State<Nip05Badge> createState() => _Nip05BadgeState();
}

class _Nip05BadgeState extends State<Nip05Badge> {
  late final Future<bool> _ok;

  @override
  void initState() {
    super.initState();
    _ok = Nip05Verifier.instance.verify(widget.identifier, widget.pubkey);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Clipboard.setData(ClipboardData(text: widget.identifier)),
      child: FutureBuilder<bool>(
        future: _ok,
        builder: (context, snap) {
          final verified = snap.data == true;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (verified)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.verified, size: 14, color: scheme.primary),
                ),
              Flexible(
                child: Text(
                  widget.identifier,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.primary),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
