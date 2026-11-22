class Hashtags {
  static final RegExp _pattern = RegExp(r'#[A-Za-z0-9_]+');

  static List<String> extract(String text) {
    final seen = <String>{};
    final out = <String>[];
    for (final match in _pattern.allMatches(text)) {
      final tag = match.group(0)!.substring(1).toLowerCase();
      if (tag.isNotEmpty && seen.add(tag)) out.add(tag);
    }
    return out;
  }
}
