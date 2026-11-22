import 'package:flutter/material.dart';

import '../../core/nostr/nostr_event.dart';
import '../widgets/molstr_avatar.dart';
import 'note_card.dart' show formatTimestamp, shortNpub;

class ArticleCard extends StatelessWidget {
  const ArticleCard({
    super.key,
    required this.article,
    required this.profile,
    required this.provenance,
    required this.loadImages,
  });

  final ArticleData article;
  final ProfileMetadata? profile;
  final String provenance;
  final bool loadImages;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final event = article.event;
    final npub = event.authorNpub;
    final name = profile?.bestName ?? shortNpub(npub);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ArticleDetailPage(article: article, profile: profile),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.article_outlined, size: 16),
                const SizedBox(width: 6),
                Text('Article', style: textTheme.labelSmall),
              ]),
              const SizedBox(height: 8),
              Text(article.title,
                  style: textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              if (article.summary != null) ...[
                const SizedBox(height: 4),
                Text(article.summary!, style: textTheme.bodyMedium),
              ],
              const SizedBox(height: 10),
              Row(children: [
                MolStrAvatar(
                    name: name,
                    picture: profile?.picture,
                    loadImages: loadImages,
                    radius: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                Text(formatTimestamp(event.createdAt),
                    style: textTheme.bodySmall),
              ]),
              if (provenance.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(provenance, style: textTheme.bodySmall),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ArticleDetailPage extends StatelessWidget {
  const ArticleDetailPage({super.key, required this.article, this.profile});

  final ArticleData article;
  final ProfileMetadata? profile;

  @override
  Widget build(BuildContext context) {
    final event = article.event;
    final npub = event.authorNpub;
    final name = profile?.bestName ?? shortNpub(npub);

    return Scaffold(
      appBar:
          AppBar(title: Text(article.title, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(name, style: Theme.of(context).textTheme.titleSmall),
          Text(
            '${formatTimestamp(event.createdAt)} · ${shortNpub(npub)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 32),
          SelectableText(event.content,
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          Text(
            'Markdown formatting and images render as plain text in this '
            'MolStr version.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
