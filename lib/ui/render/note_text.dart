import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

class NoteText extends StatelessWidget {
  const NoteText({
    super.key,
    required this.content,
    this.style,
    this.loadImages = false,
  });

  final String content;
  final TextStyle? style;
  final bool loadImages;

  static final _imagePattern = RegExp(
    r'https?://[^\s]+?\.(?:png|jpe?g|gif|webp)(?:\?[^\s]*)?',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyLarge!;
    final accent = Theme.of(context).colorScheme.primary;
    final tagStyle = TextStyle(color: accent, fontWeight: FontWeight.w700);

    final pattern = RegExp(r'#[A-Za-z0-9_]+');
    final spans = <InlineSpan>[];
    var last = 0;

    for (final match in pattern.allMatches(content)) {
      if (match.start > last) {
        spans.add(TextSpan(text: content.substring(last, match.start)));
      }
      final tag = content.substring(match.start + 1, match.end);
      if (tag.toLowerCase() == 'molstr') {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 2),
            child: SvgPicture.asset('assets/logo/molstr_icon.svg',
                width: 15, height: 15),
          ),
        ));
        spans.add(TextSpan(text: '#molstr', style: tagStyle));
      } else {
        spans.add(TextSpan(text: match.group(0), style: tagStyle));
      }
      last = match.end;
    }
    if (last < content.length) {
      spans.add(TextSpan(text: content.substring(last)));
    }

    final images =
        _imagePattern.allMatches(content).map((m) => m.group(0)!).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText.rich(TextSpan(style: base, children: spans)),
        if (images.isNotEmpty) const SizedBox(height: 8),
        for (final url in images) ...[
          if (loadImages)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url,
                width: double.infinity,
                height: 260,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _ImageHiddenTile(url: url),
              ),
            )
          else
            _ImageHiddenTile(url: url),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ImageHiddenTile extends StatelessWidget {
  const _ImageHiddenTile({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () =>
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.image_outlined),
          label: const Text('Image hidden — open externally'),
        ),
      );
}
