import 'package:flutter/material.dart';

import '../../core/nostr/interactions.dart';
import '../../core/nostr/nostr_event.dart';
import '../../core/nostr/nostr_lists.dart';
import '../../ui/render/note_card.dart';

/// Your bookmarks (private) and pinned notes (public), read from relays.
class SavedNotesPage extends StatefulWidget {
  const SavedNotesPage({
    super.key,
    required this.interactions,
    required this.loadImages,
  });

  final Interactions interactions;
  final bool loadImages;

  @override
  State<SavedNotesPage> createState() => _SavedNotesPageState();
}

class _SavedNotesPageState extends State<SavedNotesPage> {
  late final NostrListService _lists;

  List<NostrEvent> _bookmarks = const [];
  List<NostrEvent> _pinned = const [];
  Map<String, ProfileMetadata> _profiles = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lists = NostrListService(
      identityService: widget.interactions.identityService,
      relayService: widget.interactions.relayService,
      preferences: widget.interactions.preferences,
    );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final relays = widget.interactions.relays;
    final relayService = widget.interactions.relayService;

    try {
      final bookmarkIds =
          await _lists.sync(kind: kBookmarkListKind, relays: relays);
      final pinIds = await _lists.sync(kind: kPinListKind, relays: relays);

      if (bookmarkIds == null && pinIds == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Could not read your lists from your relays. Try again.';
        });
        return;
      }

      final ids = <String>{...?bookmarkIds, ...?pinIds};
      var events = <NostrEvent>[];
      if (ids.isNotEmpty) {
        final query = await relayService.queryEvents(
          {'ids': ids.take(100).toList()},
          relays,
        );
        events = query.events;
      }

      final profiles = <String, ProfileMetadata>{};
      final authors = events.map((e) => e.pubkey).toSet().take(50).toList();
      if (authors.isNotEmpty) {
        final meta = await relayService.queryEvents(
          {
            'kinds': [0],
            'authors': authors,
          },
          relays,
        );
        for (final event in meta.events) {
          final profile = ProfileMetadata.fromKind0(event);
          if (profile == null) continue;
          final existing = profiles[profile.pubkey];
          if (existing == null || profile.createdAt > existing.createdAt) {
            profiles[profile.pubkey] = profile;
          }
        }
      }

      List<NostrEvent> pick(Set<String>? wanted) => events
          .where((e) => wanted?.contains(e.id.toLowerCase()) ?? false)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;
      setState(() {
        _bookmarks = pick(bookmarkIds);
        _pinned = pick(pinIds);
        _profiles = profiles;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load saved notes.';
      });
    }
  }

  Widget _list(List<NostrEvent> notes, String emptyText) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (notes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyText, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final note in notes)
          NoteCard(
            key: ValueKey('saved:${note.id}'),
            event: note,
            profile: _profiles[note.pubkey],
            provenance: '',
            loadImages: widget.loadImages,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Saved'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(
                icon: const Icon(Icons.bookmark_outline),
                text: 'Bookmarks (${_bookmarks.length})',
              ),
              Tab(
                icon: const Icon(Icons.push_pin_outlined),
                text: 'Pinned (${_pinned.length})',
              ),
            ],
          ),
        ),
        body: InteractionsScope(
          interactions: widget.interactions,
          child: TabBarView(
            children: [
              _list(
                _bookmarks,
                'No bookmarks yet. Tap 🔖 on any note. Only you can see them.',
              ),
              _list(
                _pinned,
                'No pinned notes yet. Tap 📌 on one of your own notes.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
